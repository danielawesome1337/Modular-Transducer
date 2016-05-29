void pwmPhaser(unsigned int magRatio[8], unsigned int magPhase[8]);

void freqDrive(unsigned int t1, unsigned int t2, unsigned int halfWidth,
        out buffered port:4 p, unsigned int pulseLength);

[[combinable]]
void pwmDrive(unsigned int magRatio, unsigned int flag, out buffered port:1 p,
        unsigned int endTime, unsigned int pulseLength);
