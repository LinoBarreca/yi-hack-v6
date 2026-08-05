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
// C++ header

#ifndef _G711_AUDIO_FIFO_SERVER_MEDIA_SUBSESSION_HH
#define _G711_AUDIO_FIFO_SERVER_MEDIA_SUBSESSION_HH

#ifndef _ON_DEMAND_SERVER_MEDIA_SUBSESSION_HH
#include "OnDemandServerMediaSubsession.hh"
#endif
#ifndef _STREAM_REPLICATOR_HH
#include "StreamReplicator.hh"
#endif
#ifndef _AUDIO_G711_FIFO_SINK_HH
#include "AudioG711FifoSink.hh"   // for G711Law
#endif

class G711AudioFifoServerMediaSubsession: public OnDemandServerMediaSubsession {
public:
    static G711AudioFifoServerMediaSubsession* createNew(UsageEnvironment& env,
                                                         StreamReplicator* replicator,
                                                         G711Law law,
                                                         Boolean reuseFirstSource);

protected:
    G711AudioFifoServerMediaSubsession(UsageEnvironment& env,
                                       StreamReplicator* replicator,
                                       G711Law law,
                                       Boolean reuseFirstSource);
    virtual ~G711AudioFifoServerMediaSubsession();

protected: // redefined virtual functions
    virtual FramedSource* createNewStreamSource(unsigned clientSessionId,
                                                unsigned& estBitrate);
    virtual RTPSink* createNewRTPSink(Groupsock* rtpGroupsock,
                                      unsigned char rtpPayloadTypeIfDynamic,
                                      FramedSource* inputSource);

private:
    StreamReplicator* fReplicator;
    G711Law fLaw;
};

#endif
