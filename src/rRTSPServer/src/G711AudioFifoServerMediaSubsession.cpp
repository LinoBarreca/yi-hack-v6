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
// "liveMedia"
// Copyright (c) 1996-2022 Live Networks, Inc.  All rights reserved.
// A 'ServerMediaSubsession' object that serves the camera microphone as a
// forward G.711 audio track, read as a raw byte stream from a FIFO.
// Implementation

#include "G711AudioFifoServerMediaSubsession.hh"
#include "SimpleRTPSink.hh"

extern int debug;

G711AudioFifoServerMediaSubsession*
G711AudioFifoServerMediaSubsession::createNew(UsageEnvironment& env,
                                              StreamReplicator* replicator,
                                              G711Law law,
                                              Boolean reuseFirstSource) {
    return new G711AudioFifoServerMediaSubsession(env, replicator, law, reuseFirstSource);
}

G711AudioFifoServerMediaSubsession
::G711AudioFifoServerMediaSubsession(UsageEnvironment& env,
                                     StreamReplicator* replicator, G711Law law,
                                     Boolean reuseFirstSource)
    : OnDemandServerMediaSubsession(env, reuseFirstSource),
      fReplicator(replicator), fLaw(law) {
}

G711AudioFifoServerMediaSubsession::~G711AudioFifoServerMediaSubsession() {
}

FramedSource* G711AudioFifoServerMediaSubsession
::createNewStreamSource(unsigned /*clientSessionId*/, unsigned& estBitrate) {
    // 8000 samples/s * 8 bits, constant by definition of G.711.
    estBitrate = 64; // kbps

    FramedSource* resultSource = fReplicator->createStreamReplica();
    if (resultSource == NULL) {
        fprintf(stderr, "Failed to create G711 stream replica\n");
        return NULL;
    }
    if (debug & 4) fprintf(stderr, "G711 createStreamReplica completed successfully\n");
    return resultSource;
}

RTPSink* G711AudioFifoServerMediaSubsession
::createNewRTPSink(Groupsock* rtpGroupsock,
                   unsigned char /*rtpPayloadTypeIfDynamic*/,
                   FramedSource* /*inputSource*/) {
    // G.711 uses the STATIC payload types 0 (PCMU) and 8 (PCMA), whose 8000 Hz
    // clock rate is fixed by RFC 3551 - so the dynamic payload type the caller
    // offers is deliberately ignored. Every RTSP client knows these without any
    // out-of-band configuration, which is the whole point of choosing G.711:
    // unlike the AAC track there is no aux SDP line to discover, so this
    // subsession needs none of the ADTS one's dummy-sink startup dance.
    return SimpleRTPSink::createNew(envir(), rtpGroupsock,
                                    fLaw == G711_ULAW ? 0 : 8,
                                    8000,
                                    "audio",
                                    fLaw == G711_ULAW ? "PCMU" : "PCMA",
                                    1 /*channels*/);
}
