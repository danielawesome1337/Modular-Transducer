#ifndef TRANSDUCER_COUNT
#define TRANSDUCER_COUNT 8
#endif

unsigned int binaryChop(unsigned int topRatio);

void pwmPhaser(unsigned int magRatio[TRANSDUCER_COUNT], unsigned int magPhase[TRANSDUCER_COUNT/2]);

void freqDrive(unsigned int t1, unsigned int t2, out buffered port:4 p, unsigned int pulseLength,
        unsigned int pulseWait, unsigned int testLength, unsigned int burstLength, unsigned int burstWait, streaming chanend synchPulse);

void pwmDrive(unsigned int magRatio1, unsigned int magRatio2, unsigned int magPhase,
        out buffered port:1 p1, out buffered port:1 p2, streaming chanend synchPulse);
