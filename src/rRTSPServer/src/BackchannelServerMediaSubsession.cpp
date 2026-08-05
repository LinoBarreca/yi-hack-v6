/**********
This library is free software; you can redistribute it and/or modify it under
the terms of the GNU Lesser General Public License as published by the
Free Software Foundation; either version 3 of the License, or (at your
option) any later version. (See <http://www.gnu.org/copyleft/lesser.html>.)

This library is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public License for
more details.

You should have received a copy of the GNU Lesser General Public License
along with this library; if not, write to the Free Software Foundation, Inc.,
51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA
**********/
// yi-hack-v6 RTSP audio backchannel (ONVIF two-way / talk-back).
// BackchannelServerMediaSubsession implementation.

#include "BackchannelServerMediaSubsession.hh"
#include "SimpleRTPSource.hh"
#include "RTCP.hh"
#include "RTPInterface.hh"
#include "Groupsock.hh"
#include "GroupsockHelper.hh"

extern int debug;

// G.711 is a constant 64 kbps; RTCP gets a small share of the session bandwidth.
#define G711_BITRATE_KBPS  64

// Per-client-session receive state. One is created per SETUP and freed on
// TEARDOWN / session close; it is the streamToken. Keeping it here (not in the
// subsession) is what makes concurrent backchannel clients safe - each owns its
// own source/sink/groupsocks, so one client's teardown never frees another's.
class BackchannelStreamState {
public:
    BackchannelStreamState()
        : rtpgs(NULL), rtcpgs(NULL), source(NULL), sink(NULL), rtcp(NULL),
          tcpSocketNum(-1), rtpChannelId(0), rtcpChannelId(0), tlsState(NULL) {}
    ~BackchannelStreamState() {
        if (sink != NULL)   { sink->stopPlaying(); Medium::close(sink); }
        if (rtcp != NULL)   Medium::close(rtcp);
        if (source != NULL) Medium::close(source);
        delete rtpgs;
        delete rtcpgs;
    }
    Groupsock*         rtpgs;
    Groupsock*         rtcpgs;
    SimpleRTPSource*   source;
    AudioG711FifoSink* sink;
    RTCPInstance*      rtcp;
    int                tcpSocketNum;   // >= 0 => RTP-over-RTSP (TCP interleaved)
    unsigned char      rtpChannelId;
    unsigned char      rtcpChannelId;
    TLSState*          tlsState;
};

BackchannelServerMediaSubsession*
BackchannelServerMediaSubsession::createNew(UsageEnvironment& env,
                                            char const* fifoName, G711Law law) {
    return new BackchannelServerMediaSubsession(env, fifoName, law);
}

BackchannelServerMediaSubsession
::BackchannelServerMediaSubsession(UsageEnvironment& env,
                                   char const* fifoName, G711Law law)
    : ServerMediaSubsession(env),
      fFifoName(fifoName), fLaw(law),
      fRTPPayloadFormat(law == G711_ULAW ? 0 : 8),   // static payload types
      fRTPTimestampFrequency(8000),
      fRTPPayloadName(law == G711_ULAW ? "PCMU" : "PCMA"),
      fSDPLines(NULL), fInitialPortNum(6970) {
}

BackchannelServerMediaSubsession::~BackchannelServerMediaSubsession() {
    delete[] fSDPLines;
}

char const* BackchannelServerMediaSubsession::sdpLines(int /*addressFamily*/) {
    if (fSDPLines != NULL) return fSDPLines;

    // A backchannel audio track. "a=sendonly" per the ONVIF convention marks it
    // as a channel the client may send audio on (go2rtc / HA read it that way).
    // Port 0 / address 0.0.0.0: the real transport is negotiated at SETUP.
    char const* const sdpFmt =
        "m=audio 0 RTP/AVP %u\r\n"
        "c=IN IP4 0.0.0.0\r\n"
        "b=AS:%u\r\n"
        "a=rtpmap:%u %s/%u\r\n"
        "a=sendonly\r\n"
        "a=control:%s\r\n";
    char const* trackIdStr = trackId();
    unsigned size = strlen(sdpFmt) + 3 /*payload*/ + 20 /*bitrate*/
                  + 3 + strlen(fRTPPayloadName) + 20 /*rtpmap*/
                  + strlen(trackIdStr) + 1;
    char* lines = new char[size];
    sprintf(lines, sdpFmt,
            fRTPPayloadFormat,
            G711_BITRATE_KBPS,
            fRTPPayloadFormat, fRTPPayloadName, fRTPTimestampFrequency,
            trackIdStr);
    fSDPLines = lines;
    return fSDPLines;
}

void BackchannelServerMediaSubsession
::getStreamParameters(unsigned /*clientSessionId*/,
                      struct sockaddr_storage const& clientAddress,
                      Port const& /*clientRTPPort*/,
                      Port const& clientRTCPPort,
                      int tcpSocketNum,
                      unsigned char rtpChannelId,
                      unsigned char rtcpChannelId,
                      TLSState* tlsState,
                      struct sockaddr_storage& destinationAddress,
                      u_int8_t& /*destinationTTL*/,
                      Boolean& isMulticast,
                      Port& serverRTPPort,
                      Port& serverRTCPPort,
                      void*& streamToken) {
    if (addressIsNull(destinationAddress)) {
        destinationAddress = clientAddress;   // where our RTCP reports go
    }
    isMulticast = False;

    BackchannelStreamState* st = new BackchannelStreamState;
    st->tcpSocketNum  = tcpSocketNum;
    st->rtpChannelId  = rtpChannelId;
    st->rtcpChannelId = rtcpChannelId;
    st->tlsState      = tlsState;

    // Allocate a pair of adjacent server ports (RTP even, RTCP odd) and bind the
    // receiving groupsocks. NoReuse makes an in-use port fail to bind so concurrent
    // sessions get distinct ports. (For TCP-interleaved the UDP socket carries no
    // data - startStream redirects the source to the TCP channel - but the source
    // and RTCP objects still need a groupsock.)
    struct sockaddr_storage const& bindAddr = nullAddress(destinationAddress.ss_family);
    {
        NoReuse dummy(envir());
        for (portNumBits p = fInitialPortNum; ; p += 2) {
            serverRTPPort = p;
            st->rtpgs = new Groupsock(envir(), bindAddr, serverRTPPort, 255);
            if (st->rtpgs->socketNum() < 0) { delete st->rtpgs; st->rtpgs = NULL; continue; }

            serverRTCPPort = p + 1;
            st->rtcpgs = new Groupsock(envir(), bindAddr, serverRTCPPort, 255);
            if (st->rtcpgs->socketNum() < 0) {
                delete st->rtcpgs; st->rtcpgs = NULL;
                delete st->rtpgs;  st->rtpgs = NULL;
                continue;
            }
            break; // both bound
        }
    }

    increaseReceiveBufferTo(envir(), st->rtpgs->socketNum(), 100 * 1024);

    // Receive side: a SimpleRTPSource decoding the G.711 payload, feeding the FIFO
    // sink. RTCP sends receiver reports back to the client.
    char mimeType[16];
    snprintf(mimeType, sizeof(mimeType), "audio/%s", fRTPPayloadName);
    st->source = SimpleRTPSource::createNew(envir(), st->rtpgs, fRTPPayloadFormat,
                                            fRTPTimestampFrequency, mimeType);

    unsigned char cname[100];
    gethostname((char*)cname, sizeof(cname));
    cname[sizeof(cname) - 1] = '\0';
    st->rtcp = RTCPInstance::createNew(envir(), st->rtcpgs, G711_BITRATE_KBPS, cname,
                                       NULL /*not an RTPSink*/, st->source,
                                       False /*we're a receiver*/);

    st->sink = AudioG711FifoSink::createNew(envir(), fFifoName, fLaw);

    // Send our RTCP reports to the client's RTCP port (UDP case).
    if (tcpSocketNum < 0 && clientRTCPPort.num() != 0)
        st->rtcpgs->addDestination(clientAddress, clientRTCPPort, 0);

    streamToken = st;
}

void BackchannelServerMediaSubsession
::startStream(unsigned /*clientSessionId*/, void* streamToken,
              TaskFunc* rtcpRRHandler, void* rtcpRRHandlerClientData,
              unsigned short& rtpSeqNum, unsigned& rtpTimestamp,
              ServerRequestAlternativeByteHandler* altByteHandler,
              void* altByteHandlerClientData) {
    // These out-params describe a stream WE send; a backchannel only receives.
    rtpSeqNum = 0;
    rtpTimestamp = 0;

    BackchannelStreamState* st = (BackchannelStreamState*)streamToken;
    if (st == NULL) return;

    if (st->rtcp != NULL && rtcpRRHandler != NULL)
        st->rtcp->setRRHandler(rtcpRRHandler, rtcpRRHandlerClientData);

    // TCP interleaved transport: redirect the RTP source (and RTCP) to read from
    // the RTSP TCP connection's interleaved channels instead of the UDP groupsock.
    // Re-install the RTSP server's byte handler so ordinary RTSP commands on that
    // socket keep working - the same mechanism live555 uses for an RTP *sink* over
    // TCP, applied to our receiving source.
    if (st->tcpSocketNum >= 0) {
        if (st->source != NULL) {
            st->source->setStreamSocket(st->tcpSocketNum, st->rtpChannelId, st->tlsState);
            st->source->enableRTCPReports() = True;
            RTPInterface::setServerRequestAlternativeByteHandler(
                envir(), st->tcpSocketNum, altByteHandler, altByteHandlerClientData);
        }
        if (st->rtcp != NULL)
            st->rtcp->setStreamSocket(st->tcpSocketNum, st->rtcpChannelId, st->tlsState);
    }

    if (st->sink != NULL && st->source != NULL) {
        if (debug & 1) fprintf(stderr, "backchannel: start receiving %s -> %s (%s)\n",
                               fRTPPayloadName, fFifoName,
                               st->tcpSocketNum >= 0 ? "TCP interleaved" : "UDP");
        st->sink->startPlaying(*st->source, NULL, NULL);
    }
}

void BackchannelServerMediaSubsession
::deleteStream(unsigned /*clientSessionId*/, void*& streamToken) {
    BackchannelStreamState* st = (BackchannelStreamState*)streamToken;
    if (st == NULL) return;
    if (debug & 1) fprintf(stderr, "backchannel: stop\n");
    delete st;              // dtor stops the sink and closes source/rtcp/groupsocks
    streamToken = NULL;
}

void BackchannelServerMediaSubsession
::getRTPSinkandRTCP(void* streamToken,
                    RTPSink const*& rtpSink, RTCPInstance const*& rtcp) {
    BackchannelStreamState* st = (BackchannelStreamState*)streamToken;
    rtpSink = NULL;          // no sink: we don't send media on this track
    rtcp = (st != NULL) ? st->rtcp : NULL;
}
