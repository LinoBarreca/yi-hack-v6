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
//
// A ServerMediaSubsession that RECEIVES audio from the client instead of sending
// it. live555's OnDemandServerMediaSubsession is hardwired for the server->client
// direction (it builds an RTPSink); a backchannel is the inverse - the server
// opens an RTP port, receives the client's G.711 audio into a SimpleRTPSource,
// and feeds it to an AudioG711FifoSink that writes PCM to the speaker FIFO.
//
// The track is advertised in the SDP with "a=sendonly" per the ONVIF backchannel
// convention (Require: www.onvif.org/ver20/backchannel), which go2rtc / Home
// Assistant recognise as a two-way-audio channel to send microphone audio to.
//
// Per-client-session state (groupsocks, RTP source, sink, RTCP) lives in an opaque
// streamToken (see BackchannelStreamState in the .cpp), NOT in this subsession -
// live555 may run several client sessions on one subsession at once (go2rtc opens
// a probe connection plus the real talk connection), so shared state would let one
// teardown free objects another session is still using. Both UDP and TCP-interleaved
// transports are handled (go2rtc uses RTP-over-RTSP TCP). Codec is G.711 (PCMU
// default, payload type 0, 8 kHz mono).

#ifndef _BACKCHANNEL_SERVER_MEDIA_SUBSESSION_HH
#define _BACKCHANNEL_SERVER_MEDIA_SUBSESSION_HH

#include "ServerMediaSession.hh"
#include "AudioG711FifoSink.hh"

class BackchannelServerMediaSubsession: public ServerMediaSubsession {
public:
    static BackchannelServerMediaSubsession* createNew(UsageEnvironment& env,
                                                       char const* fifoName,
                                                       G711Law law = G711_ULAW);

protected:
    BackchannelServerMediaSubsession(UsageEnvironment& env,
                                     char const* fifoName, G711Law law);
    virtual ~BackchannelServerMediaSubsession();

protected: // redefined virtual functions (the ServerMediaSubsession interface):
    virtual char const* sdpLines(int addressFamily);
    virtual void getStreamParameters(unsigned clientSessionId,
                                     struct sockaddr_storage const& clientAddress,
                                     Port const& clientRTPPort,
                                     Port const& clientRTCPPort,
                                     int tcpSocketNum,
                                     unsigned char rtpChannelId,
                                     unsigned char rtcpChannelId,
                                     TLSState* tlsState,
                                     struct sockaddr_storage& destinationAddress,
                                     u_int8_t& destinationTTL,
                                     Boolean& isMulticast,
                                     Port& serverRTPPort,
                                     Port& serverRTCPPort,
                                     void*& streamToken);
    virtual void startStream(unsigned clientSessionId, void* streamToken,
                             TaskFunc* rtcpRRHandler,
                             void* rtcpRRHandlerClientData,
                             unsigned short& rtpSeqNum,
                             unsigned& rtpTimestamp,
                             ServerRequestAlternativeByteHandler* serverRequestAlternativeByteHandler,
                             void* serverRequestAlternativeByteHandlerClientData);
    virtual void deleteStream(unsigned clientSessionId, void*& streamToken);
    virtual void getRTPSinkandRTCP(void* streamToken,
                                   RTPSink const*& rtpSink, RTCPInstance const*& rtcp);

private:
    char const*   fFifoName;
    G711Law       fLaw;
    unsigned char fRTPPayloadFormat;      // 0 = PCMU, 8 = PCMA
    unsigned      fRTPTimestampFrequency; // 8000
    char const*   fRTPPayloadName;        // "PCMU" / "PCMA"
    char*         fSDPLines;
    portNumBits   fInitialPortNum;
};

#endif
