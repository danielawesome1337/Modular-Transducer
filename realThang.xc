/*
 * realThangv7.5.xc
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
//HALF_WIDTH is the length of the on period = off period of push/pull (50 ticks per wavelength)
//PP_DELAY is many ticks much push/pull is delayed by. Useful for settling magnitude
#define TRANSDUCER_COUNT 8
#define REF_RATE 100000000//600000000 for normal operation
#define HALF_WIDTH 25
#define PP_DELAY 100
#define DIVIDER 20000//for 50 tick wavelengths upto 2MHz

//port declarations
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

//use structs to get values back?

int main() {
    while(1)
    {
        //while(!dataIn)
        //{
        //topRatio is the frequency of push/pull rounded down to closest 100*n/255 MHz (200000 = 200kHz)
        //testLength is number of bursts in the test
        //burstLength is the number of pulses per burst
        //brf is the burst repetition frequency
        //pulseLength is the number of cycles per pulse
        //prf is the pulse repetition frequency (10000Hz max)
        unsigned int topRatio = 1000000;
        unsigned int testLength = 1000;
        unsigned int burstLength = 10;
        unsigned int brf = 100;
        unsigned int pulseLength = 2;
        unsigned int prf = 10000;

        unsigned int clockRate = binaryChop(topRatio);

        //burstWait is how many ticks to wait after burst at REF_RATE
        //pulseWait is how many ticks to wait after pulse at REF_RATE
        unsigned int burstWait = ((topRatio/brf) - (burstLength/prf))*clockRate;//-2
        unsigned int pulseWait = ((topRatio/prf) - (pulseLength/topRatio))*clockRate;//-2


        //magRatio is the pwm 'on' period in a 50 tick wavelength
        unsigned int magRatio[TRANSDUCER_COUNT] = {40,40,40,40,40,40,40,40};//0 to 50
        unsigned int magPhase[TRANSDUCER_COUNT/2] = {0,0,0,0};
        pwmPhaser(magRatio, magPhase);

        //phase is the matrix of how many ticks each port is out of phase where 0 is no shift
        unsigned int phase[TRANSDUCER_COUNT] = {0,0,0,0,0,0,0,0};//0 to 49 or 2*HALF_WIDTH - 1

        for(size_t i = 0; i < TRANSDUCER_COUNT; ++i)
        {
            phase[i]=phase[i] + PP_DELAY;//test
        }

        //second param/third param = raw clock rate in MHz
        //rounded down to closest REF_RATE/(2*n) where n = int 1 to 255
        configure_clock_rate_at_least(ppClk, topRatio, DIVIDER);//50 tick wavelength at any freq lower than 2MHz
        configure_clock_rate_at_least(pwmClk, 1000, 10);//2MHz at 50 tick wavelength

        //link 4 bit ports to push/pull clock. Initial out = 0
        for(size_t i = 0; i < TRANSDUCER_COUNT/2; ++i)
        {
            configure_out_port(pp[i], ppClk, 0);
        }
        //link 1 bit ports to pwm clock. Initial out = 0
        for(size_t i = 0; i < TRANSDUCER_COUNT; ++i)
        {
            configure_out_port(pwm[i], pwmClk, 0);
        }
        //}
        streaming chan synchPulse[4];

        //start clocks that drive outputs
        start_clock(ppClk);
        start_clock(pwmClk);

        while(1)//only once
        {
            /*STUFF HAPPENS NOW*/
            par
            {
                //2 pwm outputs per core - 4 cores
                par (size_t i = 0; i < TRANSDUCER_COUNT/2; ++i)
                        {
                    pwmDrive(magRatio[2*i], magRatio[(2*i) + 1], magPhase[i], pwm[2*i], pwm[(2*i) + 1], synchPulse[i]);
                        }

                //push/pull all run on seperate cores - 4 cores
                par (size_t i = 0; i < TRANSDUCER_COUNT/2; ++i)
                {
                    freqDrive(phase[2*i], phase[(2*i) + 1], pp[i], pulseLength, pulseWait, testLength, burstLength, burstWait, synchPulse[i]);
                }
            }
        }
    }
    return 0;
}


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
        else if(clockRateTable[middle] < clockRate && clockRateTable[middle - 1] >= clockRate)
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
                magPhase[i] == roundTo5MagRatio + 10;
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
                magPhase[i] == roundTo5MagRatio + 15;
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


void freqDrive(unsigned int t1, unsigned int t2, out buffered port:4 p, unsigned int pulseLength,
        unsigned int pulseWait, unsigned int testLength, unsigned int burstLength, unsigned int burstWait, streaming chanend synchPulse)
{
    //t1 controls the 2 LSB (least significant bit) and t2 controls the 2 MSB (most significant bit)
    signed int phaseDifference = t1-t2;
    unsigned int currentDrive = 5;//01|01 in binary
    p <: currentDrive;
    synchPulse <: 0;

    while(1) //for(size_t i=0; i < testLength; ++i)
    {
        while(1) //for(size_t i = 0; i < burstLength; ++i)
        {
            if(phaseDifference == 0)
            {
                for(size_t i = 0; i < pulseLength; ++i)
                {
                    p @ t1 <: currentDrive = 10; t1 += HALF_WIDTH;//10|10
                    p @ t1 <: currentDrive = 5; t1 += HALF_WIDTH;//01|01
                }
            }
            else if(phaseDifference == HALF_WIDTH)
            {
                for(size_t i = 0; i < pulseLength; ++i)
                {
                    p @ t2 <: currentDrive = 9; t2 += HALF_WIDTH;//10|01
                    p @ t2 <: currentDrive = 6; t2 += HALF_WIDTH;//01|10
                }
            }
            else if(phaseDifference == -HALF_WIDTH)
            {
                for(size_t i = 0; i < pulseLength; ++i)
                {
                    p @ t1 <: currentDrive = 6; t1 += HALF_WIDTH;//01|10
                    p @ t1 <: currentDrive = 9; t1 += HALF_WIDTH;//10|01
                }
            }
            else if(t1 < t2)
            {
                for(size_t i = 0; i < pulseLength; ++i)//drives push/pull for main output
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
            else//t2 > t1
            {
                for(size_t i = 0; i < pulseLength; ++i)//drives push/pull for main output
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
            t1 += pulseWait;
            t2 += pulseWait;
        }
        t1 += burstWait;
        t2 += burstWait;
    }
    synchPulse <: 1;
    return;
}


void pwmDrive(unsigned int magRatio1, unsigned int magRatio2, unsigned int magPhase,
        out buffered port:1 p1, out buffered port:1 p2, streaming chanend synchPulse)
{
    int synch = 0;
    int currentDrive[4] = {1,1,0,0};
    unsigned int t1 = 20;
    unsigned int t2 = 20 + magPhase;//test this

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

    while(1)//drives the pwm to control amplitude
    {
        select
        {
        case synchPulse :> synch:
            if(synch == 1)
            {
                return;
            }
            break;
        default:
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
