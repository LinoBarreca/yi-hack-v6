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
// AudioG711FifoSink implementation.

#include "AudioG711FifoSink.hh"

#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

extern int debug;

// One RTP audio payload is small (20-60 ms of 8 kHz G.711 = 160-480 bytes), but
// leave room for a jumbo packet. PCM is twice the byte count (16-bit vs 8-bit).
#define G711_INBUF_BYTES  2048
#define PCM_OUTBUF_BYTES  (G711_INBUF_BYTES * 2)

// ITU-T G.711 mu-law -> 14-bit-range linear PCM (sign-extended to 16-bit).
static inline short ulaw2linear(unsigned char u_val) {
    int t;
    u_val = ~u_val;
    t = ((u_val & 0x0f) << 3) + 0x84;
    t <<= (u_val & 0x70) >> 4;
    return (short)((u_val & 0x80) ? (0x84 - t) : (t - 0x84));
}

// ITU-T G.711 A-law -> linear PCM.
static inline short alaw2linear(unsigned char a_val) {
    int t, seg;
    a_val ^= 0x55;
    t = (a_val & 0x0f) << 4;
    seg = (a_val & 0x70) >> 4;
    switch (seg) {
    case 0:  t += 8; break;
    case 1:  t += 0x108; break;
    default: t += 0x108; t <<= seg - 1; break;
    }
    return (short)((a_val & 0x80) ? t : -t);
}

AudioG711FifoSink* AudioG711FifoSink::createNew(UsageEnvironment& env,
                                               char const* fifoName, G711Law law) {
    return new AudioG711FifoSink(env, fifoName, law);
}

AudioG711FifoSink::AudioG711FifoSink(UsageEnvironment& env,
                                     char const* fifoName, G711Law law)
    : MediaSink(env), fFifoName(fifoName), fLaw(law), fFd(-1) {
    fInBuf  = new unsigned char[G711_INBUF_BYTES];
    fPcmBuf = new short[G711_INBUF_BYTES];   // one PCM sample per input byte
}

AudioG711FifoSink::~AudioG711FifoSink() {
    if (fFd >= 0) ::close(fFd);   // POSIX close: Medium::close(Medium*) shadows it
    delete[] fInBuf;
    delete[] fPcmBuf;
}

Boolean AudioG711FifoSink::openFifo() {
    if (fFd >= 0) return True;
    // Non-blocking write end: campipe holds a read end open (O_RDWR), so this
    // succeeds while campipe is up. Before campipe opens the FIFO the open fails
    // with ENXIO (no reader) - we just retry on the next frame, dropping audio
    // until the consumer is there (there is nothing to play it anyway).
    fFd = open(fFifoName, O_WRONLY | O_NONBLOCK);
    if (fFd < 0 && (debug & 1))
        fprintf(stderr, "backchannel: FIFO %s not writable yet: %s\n",
                fFifoName, strerror(errno));
    return fFd >= 0;
}

Boolean AudioG711FifoSink::continuePlaying() {
    if (fSource == NULL) return False;
    fSource->getNextFrame(fInBuf, G711_INBUF_BYTES,
                          afterGettingFrame, this,
                          onSourceClosure, this);
    return True;
}

void AudioG711FifoSink::afterGettingFrame(void* clientData, unsigned frameSize,
                                          unsigned numTruncatedBytes,
                                          struct timeval /*presentationTime*/,
                                          unsigned /*durationInMicroseconds*/) {
    AudioG711FifoSink* sink = (AudioG711FifoSink*)clientData;
    sink->afterGettingFrame1(frameSize, numTruncatedBytes);
}

void AudioG711FifoSink::afterGettingFrame1(unsigned frameSize, unsigned numTruncatedBytes) {
    if (numTruncatedBytes > 0 && (debug & 1))
        fprintf(stderr, "backchannel: %u truncated bytes (frame > buffer)\n",
                numTruncatedBytes);

    if (frameSize > 0 && openFifo()) {
        unsigned n = frameSize;
        if (n > G711_INBUF_BYTES) n = G711_INBUF_BYTES;
        for (unsigned i = 0; i < n; i++)
            fPcmBuf[i] = (fLaw == G711_ULAW) ? ulaw2linear(fInBuf[i])
                                             : alaw2linear(fInBuf[i]);

        // Non-blocking write: if the consumer is slow and the pipe fills, drop
        // this frame rather than stalling the RTP receive loop (real-time audio).
        ssize_t w = write(fFd, fPcmBuf, (size_t)n * 2);
        if (w < 0) {
            if (errno == EPIPE) {          // reader vanished: reopen next time
                ::close(fFd);
                fFd = -1;
            }
            // EAGAIN (pipe full) is expected under back-pressure: just drop.
        }
    }

    // Keep receiving unless we've been asked to stop.
    continuePlaying();
}
