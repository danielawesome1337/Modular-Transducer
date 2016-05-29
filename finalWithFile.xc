/*
 * finalWithFileSlave.xc
 *
 *  Created on: 27 May 2016
 *      Author: dsdan
 */


#include <stdio.h>
#include <stdlib.h>
#include <syscall.h>
#include <xs1.h>
#include <platform.h>
#include <timer.h>
#include <math.h>
#include <print.h>
#include <functionDecs.h>

//preprocessor
//TRANSDUCER_COUNT is number of transducers per microcontroller
//REF_RATE is the reference clock rate at 100MHz
//HALF_WIDTH is half length waveperiod of push/pull (pp) in ticks
//PP_DELAY is many ticks much pp is delayed by. To precharge capacitors
//DIVIDER is the number REF_RATE is divided by to set pp frequency
//BUFFER_SIZE is input data buffer from parameters text file
//DATA_LENGTH is the number of parameters
//SOURCE is path to parameters text file
#define TRANSDUCER_COUNT 8
#define REF_RATE 100000000
#define HALF_WIDTH 25
#define PP_DELAY 100//600000000 for normal operation
#define DIVIDER 20000//20000 for 50 tick waveperiods upto 2MHz
#define BUFFER_SIZE 128
#define DATA_LENGTH 22
#define SOURCE "parameters.txt"

//port declarations
//3 1 bit ports used to communicate to master microcontroller
in port goLine = XS1_PORT_1I;
in port restartLine = XS1_PORT_1J;
in port quitLine = XS1_PORT_1K;

//4 4 bit ports for the push/pull output for 8 transducers (2 transducers per port)
out buffered port:4 pp[TRANSDUCER_COUNT/2] = {
        XS1_PORT_4A,
        XS1_PORT_4B,
        XS1_PORT_4C,
        XS1_PORT_4D
};
//8 1 bit ports for the pwm output for 8 transducers
out buffered port:1 pwm[TRANSDUCER_COUNT] = {
        XS1_PORT_1A,
        XS1_PORT_1B,
        XS1_PORT_1C,
        XS1_PORT_1D,
        XS1_PORT_1E,
        XS1_PORT_1F,
        XS1_PORT_1G,
        XS1_PORT_1H
};

//clock declarations
clock ppClk = XS1_CLKBLK_1;//push/pull clock
clock pwmClk = XS1_CLKBLK_2;//pwm clock


int main() {
    //text file reading variables
    char yesNoMaybe = 0;
    unsigned char readBuffer[BUFFER_SIZE];
    int fd;
    int flagCount = 0;
    unsigned int flags[BUFFER_SIZE];
    unsigned int data[DATA_LENGTH];

    //testLength is number of bursts in the test
    //burstLength is the number of pulses per burst
    //brf is the burst repetition frequency
    //pulseLength is the number of cycles per pulse
    //prf is the pulse repetition frequency (10000Hz max)
    unsigned int testLength;
    unsigned int burstLength;
    unsigned int brf;
    unsigned int pulseLength;
    unsigned int prf;

    //topRatio is the ideal frequency of pp
    //magRatio is an array of pwm 'on' period in a 50 tick waveperiod for every transducer
    //phase is an array of how many ticks each pp is out of phase where 0 is no shift
    //magPhase is an array that introduces phase shifts in pwm for optimising purposes
    unsigned int topRatio;
    unsigned int magRatio[TRANSDUCER_COUNT];//0 to 50
    unsigned int phase[TRANSDUCER_COUNT];//0 to 49 or 2*HALF_WIDTH - 1
    unsigned int magPhase[TRANSDUCER_COUNT/2] = {0,0,0,0};

    //clockRate is the frequency at which ppClk will run at
    //burstWait is how many ticks to wait after each burst at clockRate
    //pulseWait is how many ticks to wait after each pulse at clockRate
    unsigned int clockRate;
    unsigned int burstWait;
    unsigned int pulseWait;

    while(1)
    {
        //file reading and processing
        while(yesNoMaybe != 'y')
        {
            yesNoMaybe = 0;
            fd = _open(SOURCE, O_RDONLY, 0);
            if (fd == -1) {
                printstrln("Error: _open failed. Exiting.");
                exit(1);
            }
            _read(fd, readBuffer, BUFFER_SIZE);

            //flag every '.' in parameters text file
            for(size_t i = 0; i < BUFFER_SIZE; ++i)
            {
                if(readBuffer[i] == '.')
                {
                    flags[flagCount] = i;
                    flagCount++;
                }
            }
            //convert text between '.' (parameters) from char to int
            for(size_t i = 0; i < DATA_LENGTH; ++i)
            {
                data[i] = 0;
            }
            for(size_t i = 0; i < DATA_LENGTH; ++i)
            {
                for(size_t j = flags[i]+1; j < flags[i+1]; ++j)
                {
                    data[i] = data[i] * 10 + (readBuffer[j] - '0');
                }
                //printf("%d\n",data[i]); //debugging
            }

            if (_close(fd) != 0)
            {
                printstrln("Error: _close failed. Exiting.");
                exit(1);
            }

            testLength = data[0];
            burstLength = data[1];
            brf = data[2];
            pulseLength = data[3];
            prf = data[4];
            topRatio = data[5];
            for(size_t i = 0; i < TRANSDUCER_COUNT; ++i)
            {
                magRatio[i] = data[i + 6];
                phase[i] = data[i + 14];
            }

            //magPhase is an array that introduces phase shifts in pwm for optimising purposes
            pwmPhaser(magRatio, magPhase);
            //introduce PP_DELAY to every pp
            for(size_t i = 0; i < TRANSDUCER_COUNT; ++i)
            {
                phase[i]=phase[i] + PP_DELAY;
            }
            //clockRate is REF_RATE*topRate/DIVIDER rounded up to the closest REF_RATE/(2*n)
            //where int n = 1 to 255
            clockRate = binaryChop(topRatio);
            burstWait = ((topRatio/brf) - (burstLength/prf))*clockRate;//-2
            pulseWait = ((topRatio/prf) - (pulseLength/topRatio))*clockRate;//-2

            //second param/third param = ideal clock rate in MHz
            //this is rounded up to closest REF_RATE/(2*n) where int n = 1 to 255
            configure_clock_rate_at_least(ppClk, topRatio, DIVIDER);
            configure_clock_rate_at_least(pwmClk, 1000, 10);//2MHz at 50 tick waveperiod

            //link 4 bit ports to ppClk. Initial out = 0
            for(size_t i = 0; i < TRANSDUCER_COUNT/2; ++i)
            {
                configure_out_port(pp[i], ppClk, 0);
            }
            //link 1 bit ports to pwmClk. Initial out = 0
            for(size_t i = 0; i < TRANSDUCER_COUNT; ++i)
            {
                configure_out_port(pwm[i], pwmClk, 0);
            }

            //recieve instructions from master
            select
            {
            case goLine when pinseq(1) :> void://start outputs
                yesNoMaybe = 'y';
                break;
            case restartLine when pinseq(1) :> void://restart file process
                break;
            case quitLine when pinseq(1) :> void://quit
                exit(0);
                break;
            }
        }

        //communication between pp and pwm
        streaming chan synchPulse[4];

        start_clock(ppClk);
        start_clock(pwmClk);

        /*STUFF HAPPENS NOW*/
        par
        {
            //2 pwm outputs per core - 4 cores
            par (size_t i = 0; i < TRANSDUCER_COUNT/2; ++i)
            {
                pwmDrive(magRatio[2*i], magRatio[(2*i) + 1], magPhase[i], pwm[2*i], pwm[(2*i) + 1], synchPulse[i]);
            }
            //pp all run on seperate cores - 4 cores
            par (size_t i = 0; i < TRANSDUCER_COUNT/2; ++i)
            {
                freqDrive(phase[2*i], phase[(2*i) + 1], pp[i], pulseLength, pulseWait, testLength, burstLength, burstWait, synchPulse[i]);
            }
        }
        yesNoMaybe = 0;
    }
    return 0;
}


//find actual clockRate using binary chop algorithm
unsigned int binaryChop(unsigned int topRatio)
{
    int first = 0;
    int last = 255;
    int middle = round(first + last)/2;
    unsigned int clockRate = round((topRatio/DIVIDER)*1000000);

    unsigned int clockRateTable[256] = {REF_RATE};
    for(size_t i = 1; i < 256; ++i)
    {
        clockRateTable[i] = round(REF_RATE/(2*i));
    }

    while (first <= last)
    {
        if(clockRateTable[middle] == clockRate)
        {
            clockRate = clockRateTable[middle];
            return clockRate;
        }
        else if((clockRateTable[middle] < clockRate) && (clockRateTable[middle - 1] >= clockRate))
        {
            clockRate = clockRateTable[middle - 1];
            return clockRate;
        }
        else if(clockRateTable[middle] < clockRate)
        {
            last = middle - 1;
        }
        else
        {
            first = middle + 1;
        }
        middle = round(first + last)/2;
    }
    if (first > last)
    {
        printstr("clockRate could not be determined. Exiting.");
        exit(1);
    }
    return 0;
}


//introduces phase shifts in pwm for optimising purposes
void pwmPhaser(unsigned int magRatio[TRANSDUCER_COUNT], unsigned int magPhase[TRANSDUCER_COUNT/2])
{
    int roundTo5MagRatio = 0;
    for(size_t i = 0; i < TRANSDUCER_COUNT/2; ++i)
    {
        roundTo5MagRatio = 5*(int)round(magRatio[2*i] / 5);
        if(roundTo5MagRatio + magRatio[(2*i) + 1] + 5 != 50)
        {
            if(roundTo5MagRatio + magRatio[(2*i) + 1] + 5 - 50 == magRatio[(2*i)])
            {
                magPhase[i] == roundTo5MagRatio + 10;//arbitrary phase addition
            }
            else
            {
                magPhase[i] == roundTo5MagRatio + 5;
            }
        }
        else
        {
            if(roundTo5MagRatio + magRatio[(2*i) + 1] + 10 - 50 == magRatio[(2*i)])
            {
                magPhase[i] == roundTo5MagRatio + 15;//arbitrary phase addition
            }
            else
            {
                magPhase[i] == roundTo5MagRatio + 10;
            }
        }

        if(magPhase[i] > 50)
        {
            magPhase[i] -= 50;
        }
    }
}


//drives pwm outputs
void pwmDrive(unsigned int magRatio1, unsigned int magRatio2, unsigned int magPhase,
        out buffered port:1 p1, out buffered port:1 p2, streaming chanend synchPulse)
{
    int synch = 0;
    //current output values
    int currentDrive[4] = {1,1,0,0};
    //t1 controls first transducer, t2 controls second transducer
    unsigned int t1 = 20;//20 is arbitrarily added to minimise timing error
    unsigned int t2 = 20 + magPhase;//test this

    //saturated pwm detection
    if(magRatio1 == 50)
    {
        currentDrive[0] = 1;
        currentDrive[2] = 1;
        magRatio1 = 25;
    }
    else if(magRatio1 == 0)
    {
        currentDrive[0] = 0;
        currentDrive[2] = 0;
        magRatio1 = 25;
    }

    if(magRatio2 == 50)
    {
        currentDrive[1] = 1;
        currentDrive[3] = 1;
        magRatio2 = 25;
    }
    else if(magRatio2 == 0)
    {
        currentDrive[1] = 0;
        currentDrive[3] = 0;
        magRatio2 = 25;
    }
    unsigned int magRatioInverse1 = 50 - magRatio1;
    unsigned int magRatioInverse2 = 50 - magRatio2;

    while(1)
    {
        select
        {
        case synchPulse :> synch://returns if test has ended
        if(synch == 1)
        {
            return;
        }
        break;
        default://main drive loop
            p1 @ t1 <: currentDrive[0];
            p2 @ t2 <: currentDrive[1];
            t1 += magRatio1;
            t2 += magRatio2;
            p1 @ t1 <: currentDrive[2];
            p2 @ t2 <: currentDrive[3];
            t1 += magRatioInverse1;
            t2 += magRatioInverse2;
            break;
        }
    }
}


//drives pp outputs
void freqDrive(unsigned int t1, unsigned int t2, out buffered port:4 p, unsigned int pulseLength,
        unsigned int pulseWait, unsigned int testLength, unsigned int burstLength, unsigned int burstWait, streaming chanend synchPulse)
{
    //t1 controls the 2 LSB (first transducer) and t2 controls the 2 MSB (last transducer)
    signed int phaseDifference = t1-t2;
    unsigned int currentDrive = 5;//01|01 in binary
    p <: currentDrive;
    synchPulse <: 0;

    //main drive loop
    while(1) //for(size_t i=0; i < testLength; ++i)
    {
        while(1) //for(size_t i = 0; i < burstLength; ++i)
        {
            if(phaseDifference == 0)//if both transducers are of the same phase
            {
                for(size_t i = 0; i < pulseLength; ++i)
                {
                    p @ t1 <: currentDrive = 10; t1 += HALF_WIDTH;//10|10
                    p @ t1 <: currentDrive = 5; t1 += HALF_WIDTH;//01|01
                }
            }
            else if(phaseDifference == HALF_WIDTH)//if first transducer is 180 phase behind
            {
                for(size_t i = 0; i < pulseLength; ++i)
                {
                    p @ t2 <: currentDrive = 9; t2 += HALF_WIDTH;//10|01
                    p @ t2 <: currentDrive = 6; t2 += HALF_WIDTH;//01|10
                }
            }
            else if(phaseDifference == -HALF_WIDTH)//if second transducer is 180 phase behind
            {
                for(size_t i = 0; i < pulseLength; ++i)
                {
                    p @ t1 <: currentDrive = 6; t1 += HALF_WIDTH;//01|10
                    p @ t1 <: currentDrive = 9; t1 += HALF_WIDTH;//10|01
                }
            }
            else if(t1 < t2)
            {
                for(size_t i = 0; i < pulseLength; ++i)
                {
                    p @ t1 <: currentDrive = 6;//01|10
                    p @ t2 <: currentDrive = 10;//10|10
                    t1 += HALF_WIDTH;
                    t2 += HALF_WIDTH;
                    p @ t1 <: currentDrive = 9;//10|01
                    p @ t2 <: currentDrive = 5;//01|01
                    t1 += HALF_WIDTH;
                    t2 += HALF_WIDTH;
                }
            }
            else//if t2 > t1
            {
                for(size_t i = 0; i < pulseLength; ++i)
                {
                    p @ t2 <: currentDrive = 9;//10|01
                    p @ t1 <: currentDrive = 10;//10|10
                    t1 += HALF_WIDTH;
                    t2 += HALF_WIDTH;
                    p @ t2 <: currentDrive = 6;//01|10
                    p @ t1 <: currentDrive = 5;//01|01
                    t1 += HALF_WIDTH;
                    t2 += HALF_WIDTH;
                }
            }
            //wait before next pulse
            t1 += pulseWait;
            t2 += pulseWait;
        }
        //wait before next burst
        t1 += burstWait;
        t2 += burstWait;
    }
    synchPulse <: 1;//tell pwm to finish and return
    return;
}
