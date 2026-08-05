/*
 * Copyright (c) 2022 roleo.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, version 3.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

/*
 * Read h264 content from a pipe and send it to live555.
 */

#include "liveMedia.hh"
#include "BasicUsageEnvironment.hh"
#include "StreamReplicator.hh"
#include "DummySink.hh"
#include "ADTSAudioFifoServerMediaSubsession.hh"
#include "ADTSAudioFifoSource.hh"
#include "G711AudioFifoServerMediaSubsession.hh"
#include "ByteStreamFifoSource.hh"
#include "H264VideoFifoServerMediaSubsession.hh"
#include "BackchannelServerMediaSubsession.hh"

#include <sys/stat.h>
#include <getopt.h>
#include <errno.h>
#include <limits.h>

#define RESOLUTION_NONE 0
#define RESOLUTION_LOW  360
#define RESOLUTION_HIGH 1080
#define RESOLUTION_BOTH 1440

// Forward audio codec. The camera side (campipe) produces exactly one of these
// and writes it to the matching FIFO; -a selects which track we advertise.
#define AUDIO_NONE 0
#define AUDIO_AAC  1
#define AUDIO_G711 2

// One 20 ms G.711 packet: 8000 samples/s * 0.02 s * 1 byte/sample. Feeding the
// RTP sink in these units is what makes the packet cadence right; the payload has
// no framing of its own to derive it from.
#define G711_FRAME_BYTES  160
#define G711_FRAME_USECS  20000

int debug = 0;

UsageEnvironment* env;

// To make the second and subsequent client for each stream reuse the same
// input stream as the first client (rather than playing the file from the
// start for each client), change the following "False" to "True":
Boolean reuseFirstSource = True;

// To stream *only* MPEG-1 or 2 video "I" frames
// (e.g., to reduce network bandwidth),
// change the following "False" to "True":
Boolean iFramesOnly = False;

StreamReplicator* startReplicatorStream(const char* inputAudioFileName) {
    // Create a single ADTSAudioFifo source that will be replicated for mutliple streams
    ADTSAudioFifoSource* adtsSource = ADTSAudioFifoSource::createNew(*env, inputAudioFileName);
    if (adtsSource == NULL) {
        // Give up here: a replicator built on a NULL source crashes as soon as
        // anything pulls from it, and the caller turns audio off on NULL.
        *env << "Failed to create Fifo Source \n";
        return NULL;
    }

    // Create and start the replicator that will be given to each subsession
    StreamReplicator* replicator = StreamReplicator::createNew(*env, adtsSource);

    // Keep the replicator DRAINED even with no client attached, by feeding one
    // replica into a sink that throws the frames away.
    //
    // This is not optional. Without it the ADTS source only advances when some
    // client pulls, so the FIFO backs up and its presentation times fall behind
    // the wall clock, while the (separate) H.264 source stays current. A client
    // that then asks for video+audio gets audio stamped seconds in the past and
    // its muxer discards the lot: measured on hardware as "227 packets read,
    // 0 packets muxed" with the timeline starting at -12.67s, i.e. silent
    // recordings and a stalled recorder, even though the audio track itself was
    // perfectly fine when pulled on its own.
    FramedSource* source = replicator->createStreamReplica();
    MediaSink* sink = DummySink::createNew(*env, "dummy");
    sink->startPlaying(*source, NULL, NULL);

    return replicator;
}

// The G.711 payload is a bare byte stream - no sync word, no frame header - so
// unlike the ADTS source there is nothing to parse and nothing to discover for
// the SDP. We only have to hand it to the RTP sink in packet-sized bites.
StreamReplicator* startG711ReplicatorStream(const char* inputAudioFileName) {
    ByteStreamFifoSource* g711Source =
        ByteStreamFifoSource::createNew(*env, inputAudioFileName,
                                        G711_FRAME_BYTES, G711_FRAME_USECS);
    if (g711Source == NULL) {
        *env << "Failed to create G711 Fifo Source \n";
        return NULL;
    }

    StreamReplicator* replicator = StreamReplicator::createNew(*env, g711Source);

    // Same reason as the AAC replicator above: drain it continuously so the
    // source's presentation times track the wall clock instead of drifting into
    // the past whenever no client is attached.
    FramedSource* source = replicator->createStreamReplica();
    MediaSink* sink = DummySink::createNew(*env, "dummy");
    sink->startPlaying(*source, NULL, NULL);

    return replicator;
}

static void announceStream(RTSPServer* rtspServer, ServerMediaSession* sms,
                                char const* streamName, char const* inputFileName, int audio) {
    char* url = rtspServer->rtspURL(sms);
    UsageEnvironment& env = rtspServer->envir();
    env << "\n\"" << streamName << "\" stream, from the file \""
        << inputFileName << "\"\n";
    if (audio == AUDIO_AAC)
        env << "AAC audio enabled\n";
    else if (audio == AUDIO_G711)
        env << "G.711 audio enabled\n";
    env << "Play this stream using the URL \"" << url << "\"\n";
    delete[] url;
}

// Attach whichever forward audio track is configured. The forward G.711 track is
// PCMA, because the SoC's AENC produces A-law - verified from the wire bytes (see
// the note in campipe's ai_loop_g711). That is a different companding from the
// backchannel's PCMU, which is fine: they are independent tracks and each names
// what it actually carries. Do not "align" them without re-checking the bytes.
static void addAudioSubsession(ServerMediaSession* sms, int audio,
                               StreamReplicator* replicator) {
    if (audio == AUDIO_AAC) {
        sms->addSubsession(ADTSAudioFifoServerMediaSubsession
                               ::createNew(*env, replicator, reuseFirstSource));
    } else if (audio == AUDIO_G711) {
        sms->addSubsession(G711AudioFifoServerMediaSubsession
                               ::createNew(*env, replicator, G711_ALAW, reuseFirstSource));
    }
}

void print_usage(char *progname)
{
    fprintf(stderr, "\nUsage: %s [-r RES] [-a AUDIO] [-p PORT] [-u USER] [-w PASSWORD] [-d LEVEL]\n\n", progname);
    fprintf(stderr, "\t-r RES,  --resolution RES\n");
    fprintf(stderr, "\t\tset resolution: low, high, both or none (default high)\n");
    fprintf(stderr, "\t-a AUDIO,  --audio AUDIO\n");
    fprintf(stderr, "\t\tset forward audio codec: no, aac or g711 (default aac)\n");
    fprintf(stderr, "\t-b BACKCHANNEL,  --backchannel BACKCHANNEL\n");
    fprintf(stderr, "\t\tset ONVIF two-way audio backchannel: yes or no (default no)\n");
    fprintf(stderr, "\t-p PORT, --port PORT\n");
    fprintf(stderr, "\t\tset TCP port (default 554)\n");
    fprintf(stderr, "\t-u USER, --user USER\n");
    fprintf(stderr, "\t\tset username\n");
    fprintf(stderr, "\t-w PASSWORD, --password PASSWORD\n");
    fprintf(stderr, "\t\tset password\n");
    fprintf(stderr, "\t-d LEVEL, --debug LEVEL\n");
    fprintf(stderr, "\t\tenable debug, LEVEL = [1..7]\n");
    fprintf(stderr, "\t-h,      --help\n");
    fprintf(stderr, "\t\tprint this help\n");
}

int main(int argc, char** argv)
{
    char *str;
    int nm;
    char user[65];
    char pwd[65];
    int c;
    char *endptr;

    char const* inputAudioFileName = "/tmp/aac_audio_fifo";
    char const* inputG711FileName = "/tmp/g711_audio_fifo";
    char const* backchannelFifoName = "/tmp/audio_out_fifo";
    struct stat stat_buffer;

    // Setting default
    int resolution = RESOLUTION_HIGH;
    int audio = AUDIO_AAC;
    int backchannel = 0;   // ONVIF two-way audio (talk-back); opt-in
    int port = 554;

    memset(user, 0, sizeof(user));
    memset(pwd, 0, sizeof(pwd));

    while (1) {
        static struct option long_options[] =
        {
            {"resolution",  required_argument, 0, 'r'},
            {"audio",  required_argument, 0, 'a'},
            {"backchannel",  required_argument, 0, 'b'},
            {"port",  required_argument, 0, 'p'},
            {"user",  required_argument, 0, 'u'},
            {"password",  required_argument, 0, 'w'},
            {"debug",  required_argument, 0, 'd'},
            {"help",  no_argument, 0, 'h'},
            {0, 0, 0, 0}
        };
        /* getopt_long stores the option index here. */
        int option_index = 0;

        c = getopt_long (argc, argv, "r:a:b:p:u:w:d:h",
                         long_options, &option_index);

        /* Detect the end of the options. */
        if (c == -1)
            break;

        switch (c) {
        case 'r':
            if (strcasecmp("low", optarg) == 0) {
                resolution = RESOLUTION_LOW;
            } else if (strcasecmp("high", optarg) == 0) {
                resolution = RESOLUTION_HIGH;
            } else if (strcasecmp("both", optarg) == 0) {
                resolution = RESOLUTION_BOTH;
            } else if (strcasecmp("none", optarg) == 0) {
                resolution = RESOLUTION_NONE;
            }
            break;

        case 'a':
            if (strcasecmp("no", optarg) == 0) {
                audio = AUDIO_NONE;
            } else if (strcasecmp("aac", optarg) == 0) {
                audio = AUDIO_AAC;
            } else if (strcasecmp("g711", optarg) == 0) {
                audio = AUDIO_G711;
            } else if (strcasecmp("yes", optarg) == 0) {
                // Legacy spelling of "aac" - config files written before the
                // codec became explicit still say yes, so keep honouring it.
                audio = AUDIO_AAC;
            }
            break;

        case 'b':
            if (strcasecmp("no", optarg) == 0) {
                backchannel = 0;
            } else if (strcasecmp("yes", optarg) == 0) {
                backchannel = 1;
            }
            break;

        case 'p':
            errno = 0;    /* To distinguish success/failure after call */
            port = strtol(optarg, &endptr, 10);

            /* Check for various possible errors */
            if ((errno == ERANGE && (port == LONG_MAX || port == LONG_MIN)) || (errno != 0 && port == 0)) {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            if (endptr == optarg) {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            break;

        case 'u':
            if (strlen(optarg) < sizeof(user)) {
                strcpy(user, optarg);
            }
            break;

        case 'w':
            if (strlen(optarg) < sizeof(pwd)) {
                strcpy(pwd, optarg);
            }
            break;

        case 'd':
            errno = 0;    /* To distinguish success/failure after call */
            debug = strtol(optarg, &endptr, 10);

            /* Check for various possible errors */
            if ((errno == ERANGE && (debug == LONG_MAX || debug == LONG_MIN)) || (errno != 0)) {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            if (endptr == optarg) {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            if ((debug < 0) || (debug > 7)) {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            break;

        case 'h':
            print_usage(argv[0]);
            return -1;
            break;

        case '?':
            /* getopt_long already printed an error message. */
            break;

        default:
            print_usage(argv[0]);
            return -1;
        }
    }

    // Get parameters from environment
    str = getenv("RRTSP_RES");
    if (str != NULL) {
        if (strcasecmp("low", str) == 0) {
            resolution = RESOLUTION_LOW;
        } else if (strcasecmp("high", str) == 0) {
            resolution = RESOLUTION_HIGH;
        } else if (strcasecmp("both", str) == 0) {
            resolution = RESOLUTION_BOTH;
        } else if (strcasecmp("none", str) == 0) {
            resolution = RESOLUTION_NONE;
        }
    }

    // Same codec vocabulary as -a, which this overrides: it must know every value
    // the option knows, or an env-driven launch silently loses the g711 track.
    str = getenv("RRTSP_AUDIO");
    if (str != NULL) {
        if (strcasecmp("no", str) == 0) {
            audio = AUDIO_NONE;
        } else if (strcasecmp("aac", str) == 0) {
            audio = AUDIO_AAC;
        } else if (strcasecmp("g711", str) == 0) {
            audio = AUDIO_G711;
        } else if (strcasecmp("yes", str) == 0) {
            audio = AUDIO_AAC;      // legacy spelling of "aac"
        }
    }

    str = getenv("RRTSP_BACKCHANNEL");
    if (str != NULL) {
        if (strcasecmp("no", str) == 0) {
            backchannel = 0;
        } else if (strcasecmp("yes", str) == 0) {
            backchannel = 1;
        }
    }

    str = getenv("RRTSP_PORT");
    if ((str != NULL) && (sscanf (str, "%i", &nm) == 1) && (nm >= 0)) {
        port = nm;
    }

    str = getenv("RRTSP_DEBUG");
    if ((str != NULL) && (sscanf (str, "%i", &nm) == 1) && (nm == 1)) {
        debug = nm;
    }

    str = getenv("RRTSP_USER");
    if ((str != NULL) && (strlen(str) < sizeof(user))) {
        strcpy(user, str);
    }

    str = getenv("RRTSP_PWD");
    if ((str != NULL) && (strlen(str) < sizeof(pwd))) {
        strcpy(pwd, str);
    }

    if ((resolution == RESOLUTION_NONE) && (audio == 0)) {
        fprintf(stderr, "Nothing to stream: select valid resolution or enable audio\n");
        return -2;
    }

    // Begin by setting up our usage environment:
    TaskScheduler* scheduler = BasicTaskScheduler::createNew();
    env = BasicUsageEnvironment::createNew(*scheduler);

    // Each codec has its own FIFO, because campipe produces one or the other and
    // the two payloads are not interchangeable on the wire.
    if (audio == AUDIO_G711) inputAudioFileName = inputG711FileName;

    // If fifo doesn't exist, disable audio
    if (audio != AUDIO_NONE && stat (inputAudioFileName, &stat_buffer) != 0) {
        *env << "Audio fifo does not exist, disabling audio.";
        audio = AUDIO_NONE;
    }

    UserAuthenticationDatabase* authDB = NULL;

    if ((user[0] != '\0') && (pwd[0] != '\0')) {
        // To implement client access control to the RTSP server, do the following:
        authDB = new UserAuthenticationDatabase;
        authDB->addUserRecord(user, pwd);
        // Repeat the above with each <username>, <password> that you wish to allow
        // access to the server.
    }

    // Create the RTSP server:
    RTSPServer* rtspServer = RTSPServer::createNew(*env, port, authDB);
    if (rtspServer == NULL) {
        *env << "Failed to create RTSP server: " << env->getResultMsg() << "\n";
        exit(1);
    }

    StreamReplicator* replicator = NULL;
    if (audio == AUDIO_AAC) {
        if (debug & 1) fprintf(stderr, "Starting aac replicator\n");
        // Create and start the replicator that will be given to each subsession
        replicator = startReplicatorStream(inputAudioFileName);
    } else if (audio == AUDIO_G711) {
        if (debug & 1) fprintf(stderr, "Starting g711 replicator\n");
        replicator = startG711ReplicatorStream(inputAudioFileName);
    }
    // A replicator that failed to build must turn the audio OFF, not be handed to
    // a subsession: both subsessions dereference it unconditionally when a client
    // SETUPs the track (fReplicator->createStreamReplica()), so advertising the
    // track anyway would segfault the server on the first client instead of just
    // serving video.
    if (audio != AUDIO_NONE && replicator == NULL) {
        *env << "Failed to start the audio replicator, disabling audio.\n";
        audio = AUDIO_NONE;
    }

    char const* descriptionString = "Session streamed by \"rRTSPServer\"";

    // First, make sure that the RTPSinks' buffers will be large enough to handle the huge size of DV frames (as big as 288000).
    OutPacketBuffer::maxSize = 262144;

    // Set up each of the possible streams that can be served by the
    // RTSP server.  Each such stream is implemented using a
    // "ServerMediaSession" object, plus one or more
    // "ServerMediaSubsession" objects for each audio/video substream.

    // A H.264 video elementary stream:
    if ((resolution == RESOLUTION_HIGH) || (resolution == RESOLUTION_BOTH))
    {
        char const* streamName = "ch0_0.h264";
        char const* inputFileName = "/tmp/h264_high_fifo";

        ServerMediaSession* sms_high
            = ServerMediaSession::createNew(*env, streamName, streamName,
                                    descriptionString);
        sms_high->addSubsession(H264VideoFifoServerMediaSubsession
                                ::createNew(*env, inputFileName, reuseFirstSource));
        addAudioSubsession(sms_high, audio, replicator);
        if (backchannel == 1) {
            sms_high->addSubsession(BackchannelServerMediaSubsession
                                       ::createNew(*env, backchannelFifoName));
        }
        rtspServer->addServerMediaSession(sms_high);

        announceStream(rtspServer, sms_high, streamName, inputFileName, audio);
    }

    // A H.264 video elementary stream:
    if ((resolution == RESOLUTION_LOW) || (resolution == RESOLUTION_BOTH))
    {
        char const* streamName = "ch0_1.h264";
        char const* inputFileName = "/tmp/h264_low_fifo";

        ServerMediaSession* sms_low
        = ServerMediaSession::createNew(*env, streamName, streamName,
                                descriptionString);
        sms_low->addSubsession(H264VideoFifoServerMediaSubsession
                                ::createNew(*env, inputFileName, reuseFirstSource));
        addAudioSubsession(sms_low, audio, replicator);
        if (backchannel == 1) {
            sms_low->addSubsession(BackchannelServerMediaSubsession
                                       ::createNew(*env, backchannelFifoName));
        }
        rtspServer->addServerMediaSession(sms_low);

        announceStream(rtspServer, sms_low, streamName, inputFileName, audio);
    }

    // An ADTS  audio elementary stream:
    if (audio != 0)
    {
        char const* streamName = "ch0_2.h264";

        ServerMediaSession* sms_audio
            = ServerMediaSession::createNew(*env, streamName, streamName,
                                              descriptionString);
        addAudioSubsession(sms_audio, audio, replicator);
        rtspServer->addServerMediaSession(sms_audio);

        announceStream(rtspServer, sms_audio, streamName, inputAudioFileName, audio);
    }

    // Also, attempt to create a HTTP server for RTSP-over-HTTP tunneling.
    // Try first with the default HTTP port (80), and then with the alternative HTTP
    // port numbers (8000 and 8080).
/*
    if (rtspServer->setUpTunnelingOverHTTP(80) || rtspServer->setUpTunnelingOverHTTP(8000) || rtspServer->setUpTunnelingOverHTTP(8080)) {
        *env << "\n(We use port " << rtspServer->httpServerPortNum() << " for optional RTSP-over-HTTP tunneling.)\n";
    } else {
        *env << "\n(RTSP-over-HTTP tunneling is not available.)\n";
    }
*/
    env->taskScheduler().doEventLoop(); // does not return

    return 0; // only to prevent compiler warning
}
