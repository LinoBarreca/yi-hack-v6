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
// A MediaSink that receives an incoming G.711 (PCMU/PCMA) audio stream, decodes
// it to 16-bit signed little-endian PCM, and writes it to a FIFO. On the y20 the
// FIFO is /tmp/audio_out_fifo, which campipe's ao_thread drains and plays through
// the speaker. This is the receive end of the backchannel: the RTP frames come
// from a SimpleRTPSource fed by the client's talk audio.

#ifndef _AUDIO_G711_FIFO_SINK_HH
#define _AUDIO_G711_FIFO_SINK_HH

#include "MediaSink.hh"

// Which G.711 companding law the incoming payload uses.
typedef enum { G711_ULAW, G711_ALAW } G711Law;

class AudioG711FifoSink: public MediaSink {
public:
    static AudioG711FifoSink* createNew(UsageEnvironment& env,
                                        char const* fifoName,
                                        G711Law law);

protected:
    AudioG711FifoSink(UsageEnvironment& env, char const* fifoName, G711Law law);
    virtual ~AudioG711FifoSink();

protected: // redefined virtual functions:
    virtual Boolean continuePlaying();

private:
    static void afterGettingFrame(void* clientData, unsigned frameSize,
                                  unsigned numTruncatedBytes,
                                  struct timeval presentationTime,
                                  unsigned durationInMicroseconds);
    void afterGettingFrame1(unsigned frameSize, unsigned numTruncatedBytes);

    // (Re)open the FIFO for non-blocking writing; returns True once fFd >= 0.
    Boolean openFifo();

private:
    char const* fFifoName;
    G711Law     fLaw;
    int         fFd;
    unsigned char* fInBuf;   // raw G.711 bytes as received over RTP
    short*         fPcmBuf;  // decoded 16-bit PCM
};

#endif
