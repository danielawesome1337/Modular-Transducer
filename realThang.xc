/*
 * realThangv7.xc
 *
 *  Created on: 25 May 2016
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
#define TRANSDUCER_COUNT 8
#define REF_RATE 100000000
#define HALF_WIDTH 25

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
            unsigned int topRatio = 2000000;
            unsigned int testLength = 1000;
            unsigned int burstLength = 10;
            unsigned int brf = 100;
            unsigned int pulseLength = 3;
            unsigned int prf = 10000;

            //burstWait is how many ticks to wait after burst at REF_RATE
            //pulseWait is how many ticks to wait after pulse at REF_RATE
            unsigned int endTime = (REF_RATE*pulseLength/topRatio) + (100*pulseLength) - 1;
            unsigned int burstWait = (REF_RATE/brf) - (REF_RATE*burstLength/prf) - (burstLength*100*pulseLength);
            unsigned int pulseWait = (REF_RATE/prf) - endTime;

            //magRatio is the pwm 'on' period in a 50 tick wavelength
            unsigned int magRatio[TRANSDUCER_COUNT] = {40,40,40,40,40,40,40,40};//0 to 50
            unsigned int magPhase[TRANSDUCER_COUNT] = {0,0,0,0,0,0,0,0};
            pwmPhaser(magRatio, magPhase);

            //phase is the matrix of how many ticks (0 to 49 or 2*HALF_WIDTH - 1) each port is out of phase where 0 is no shift
            unsigned int phase[TRANSDUCER_COUNT] = {0,0,0,0,0,0,0,0};

            for(size_t i = 0; i < TRANSDUCER_COUNT; ++i)
            {
                phase[i]=phase[i]+100;//test
            }

            //second param/third param = raw clock rate in MHz
            configure_clock_rate_at_least(ppClk, topRatio, 20000);//50 tick wavelength at any freq lower than 2MHz
            configure_clock_rate_at_least(pwmClk, 1000, 10);//2MHz at 50 tick wavelength

            //link 4 bit ports to push/pull clock. Initial out = 0
            for(size_t i = 0; i < TRANSDUCER_COUNT/2; ++i)
            {
                configure_out_port(pp[i], ppClk, 0);
            }
            //link 1 bit ports to pwm clock. Initial out = 0
            for(size_t i = 0; i < TRANSDUCER_COUNT; ++i)
            {
                configure_out_port(pwm[i], ppClk, 0);
            }
        //}

        //start clocks that drive outputs
        start_clock(ppClk);
        start_clock(pwmClk);

        while(1)//for(size_t i=0; i < testLength; ++i)
        {
            for(size_t i = 0; i < burstLength; ++i)
            {
                /*STUFF HAPPENS NOW*/
                par
                {
                    //2 pwm outputs per core - 4 cores
                    [[combine]]
                     par (size_t i = 0; i < 2; ++i)
                     {
                        pwmDrive(magRatio[i], magPhase[i], pwm[i], endTime);
                     }
                    [[combine]]
                     par (size_t i = 2; i < 4; ++i)
                     {
                        pwmDrive(magRatio[i], magPhase[i], pwm[i], endTime);
                     }
                    [[combine]]
                     par (size_t i = 4; i < 6; ++i)
                     {
                        pwmDrive(magRatio[i], magPhase[i], pwm[i], endTime);
                     }
                    [[combine]]
                     par (size_t i = 6; i < 8; ++i)
                     {
                        pwmDrive(magRatio[i], magPhase[i], pwm[i], endTime);
                     }

                    //push/pull all run on seperate cores - 4 cores
                    par (size_t i = 0; i < TRANSDUCER_COUNT/2; ++i)
                    {
                        freqDrive(phase[2*i], phase[(2*i) + 1], pp[i], pulseLength);
                    }
                }
                delay_ticks(pulseWait);//test
            }
            delay_ticks(burstWait);//test
        }
    }
    return 0;
}


void pwmPhaser(unsigned int magRatio[TRANSDUCER_COUNT], unsigned int magPhase[TRANSDUCER_COUNT])
{
    int roundTo5MagRatio = 0;
    for(size_t i = 0; i < TRANSDUCER_COUNT/2; ++i)
    {
        roundTo5MagRatio = 5*(int)round(magRatio[2*i] / 5);
        if(roundTo5MagRatio + magRatio[(2*i) + 1] + 5 != 50)
        {
            if(roundTo5MagRatio + magRatio[(2*i) + 1] + 5 - 50 == magRatio[(2*i)])
            {
                magPhase[(2*i) + 1] == roundTo5MagRatio + 10;
            }
            else
            {
                magPhase[(2*i) + 1] == roundTo5MagRatio + 5;
            }
        }
        else
        {
            if(roundTo5MagRatio + magRatio[(2*i) + 1] + 10 - 50 == magRatio[(2*i)])
            {
                magPhase[(2*i) + 1] == roundTo5MagRatio + 15;
            }
            else
            {
                magPhase[(2*i) + 1] == roundTo5MagRatio + 10;
            }
        }

        if(magPhase[(2*i) + 1] > 50)
        {
            magPhase[(2*i) + 1] -= 50;
        }

    }
}


void freqDrive(unsigned int t1, unsigned int t2, out buffered port:4 p, unsigned int pulseLength)
{
    //t1 controls the 2 LSB (least significant bit) and t2 controls the 2 MSB (most significant bit)
    unsigned int currentDrive = 5;//01|01 Binary
    p <: 5;
    signed int phaseDifference = t1-t2;
    if(t1 == t2)
    {
        for(size_t i = 0; i < pulseLength; ++i)
        {
            p @ t1 <: currentDrive = 10; t1 += HALF_WIDTH;//10|10
            p @ t1 <: currentDrive = 5; t1 += HALF_WIDTH;//01|01
        }
    }
    else if(abs(phaseDifference) == HALF_WIDTH)
    {
        if(phaseDifference == HALF_WIDTH)
        {
            for(size_t i = 0; i < pulseLength; ++i)
            {
                p @ t2 <: currentDrive = 9; t2 += HALF_WIDTH;//10|01
                p @ t2 <: currentDrive = 6; t2 += HALF_WIDTH;//01|10
            }
        }
        else
        {
            for(size_t i = 0; i < pulseLength; ++i)
            {
                p @ t1 <: currentDrive = 6; t1 += HALF_WIDTH;//01|10
                p @ t1 <: currentDrive = 9; t1 += HALF_WIDTH;//10|01
            }
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
    else
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
    return;
}


[[combinable]]
 void pwmDrive(unsigned int magRatio, unsigned int magPhase, out buffered port:1 p,
         unsigned int endTime)
{
    unsigned int t = 20 + magPhase;//test this
    unsigned int magRatioInverse = 50 - magRatio;
    unsigned int tEnd = endTime;//test this
    unsigned int currentDrive = 0;
    timer tmr;

    while(1)//drives the pwm to control amplitude
    {
        select{
        case tmr when timerafter(0) :> void:
            if(t >= tEnd)
            {
                p @ t <: 0;
                return;
            }
            else if(currentDrive == 0 && magRatio != 0)
            {
                p @ t <: currentDrive = 1;
                t += magRatio;
            }
            else if(magRatio != 50)
            {
                p @ t <: currentDrive = 0;
                t += magRatioInverse;
            }
            break;
        }
    }
}
