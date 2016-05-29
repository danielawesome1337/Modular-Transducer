#ifndef _TRANSDUCER_COUNT
#define TRANSDUCER_COUNT 8
#endif

void pwmPhaser(unsigned int magRatio[TRANSDUCER_COUNT], unsigned int magPhase[TRANSDUCER_COUNT]);

void freqDrive(unsigned int t1, unsigned int t2, out buffered port:4 p, unsigned int pulseLength);

[[combinable]]
 void pwmDrive(unsigned int magRatio,  unsigned int magPhase, out buffered port:1 p,
         unsigned int endTime);
