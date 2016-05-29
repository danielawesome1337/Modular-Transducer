/*
 * realThangv4.xc
 *
 *  Created on: 22 Mar 2016
 *      Author: Daniel
 */

//ADD: burst functionality
#include <xs1.h>
#include <stdio.h>
#include <platform.h>
#include <functionDecs.h>
#include <timer.h>

//4 4 bit ports for the push/pull output for 8 transducers (2 transducers per port)
out buffered port:4 PP[4] = {
        XS1_PORT_4A,
        XS1_PORT_4B,
        XS1_PORT_4C,
        XS1_PORT_4D
};

//8 1 bit ports for the PWM output for 8 transducers
out buffered port:1 PWM[8] = {
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
clock PPclk = XS1_CLKBLK_1;//push/pull clock
clock PWMclk = XS1_CLKBLK_2;//PWM clock
clock PRFclk = XS1_CLKBLK_3;//pulse repetition frequency clock

int main() {
    while(1)
    {
        //READ IN topRatio.
        //READ IN burstLength
        //READ IN PRF.
        //READ IN magRatio.
        //READ IN pulseLength
        //READ IN phase.


        //topRatio is the exact frequency of push/pull (200000 = 200kHz)
        //pulseNumber is the number of pulses per test
        //PRF is the pulse repetition frequency
        unsigned long int topRatio = 2000000; //,pulseLength = 1000, PRF = 1000;

        //halfWidth is the length of the on period = off period of push/pull (50 ticks per wavelength)
        //pulseLength is the length of each pulse in units of wavelengths
        unsigned int halfWidth = 25; //,pulseLength=10;

        //phase is the matrix of how many ticks each port is out of phase where 0 is no shift
        unsigned int phase[8] = {0,0,0,0,0,0,0,0};//A,B,C,D WORKS

        //magRatio is the PWM on period out of 50
        //magRatio should be a matrix for every pulse in a set of pulses
        unsigned int magRatio[8] = {40,40,40,40,40,40,40,40};

        //link 4 bit ports to push/pull clock. Initial out = 0
        for(size_t i = 0; i < 4; i++)
        {
            configure_out_port(PP[i], PPclk, 0);
        }
        //link 1 bit ports to PWM clock. Initial out = 0
        for(size_t i = 0; i < 8; i++)
        {
            configure_out_port(PWM[i], PWMclk, 0);
        }

        while(1)//ADD: while in burstLength (#pulses)
        {
            configure_clock_rate_at_least(PPclk,topRatio,20000);//1000000/50=20000 so 50 tick wavelength for every freq
            configure_clock_rate_at_least(PWMclk,1000,10);//2MHz at 50 tick wavelength
            //ADD: configure_clock_rate_at_least(PRFclk,PRF,20000);

            while(1)//ADD: while in pulseLength (#cycle) for(size_t i = 0; i < pulseLength; i++)
            {
                //ADD: start_clock(PRFclk);
                //ADD: @ PRFclk whatever
                start_clock(PPclk);
                start_clock(PWMclk);
                //ADD: if(magRatio) is 50 or 0

                /*STUFF HAPPENS NOW*/
                par
                {
                    //PWM all run on 1 core
                    [[combine]]
                     par (size_t i = 0; i < 8; i++)
                     {
                        PWMdrive(magRatio[i], PWM[i]);
                     }
                    //push/pull run on seperate cores
                    par (size_t i = 0; i < 4; i++)
                    {
                        freqDrive(phase[2*i], phase[(2*i)+1], halfWidth, PP[i]);
                    }
                }
            }
        }
    }
    return 0;
}


void freqDrive(unsigned int phase1, unsigned int phase2, unsigned int halfWidth, out buffered port:4 p)//pulseLength
{
    //t1 controls the 2 LSB (least significant bit) and t2 controls the 2 MSB (most significant bit)
    unsigned long int t1 = 200+phase1;//200 tick delay in push/pull start
    unsigned long int t2 = 200+phase2;
    unsigned int currentDrive = 5;//01|01 Binary
    if (t1==t2)
    {
        while(1)
        {
            p @ t1 <: currentDrive=10; t1+=halfWidth;//10|10
            p @ t1 <: currentDrive=5; t1+=halfWidth;//01|01
        }
    }
    else
    {
        while (1)//drives push/pull for main output (pulseLength should go here)
        {
            if(t1<t2)//LSB flip
            {
                switch(currentDrive)
                {
                case 10://10|10
                    p @ t1 <: currentDrive=9;//10|01
                    t1+=halfWidth;
                    break;
                case 9://10|01
                    p @ t1 <: currentDrive=10;//10|10
                    t1+=halfWidth;
                    break;
                case 6://01|10
                    p @ t1 <: currentDrive=5;//01|01
                    t1+=halfWidth;
                    break;
                case 5://01|01
                    p @ t1 <: currentDrive=6;//01|10
                    t1+=halfWidth;
                    break;
                }
            }
            else//MSB flip
            {
                switch(currentDrive)
                {
                case 10://10|10
                    p @ t2 <: currentDrive=6;//01|10
                    t2+=halfWidth;
                    break;
                case 9://10|01
                    p @ t2 <: currentDrive=5;//01|01
                    t2+=halfWidth;
                    break;
                case 6://01|10
                    p @ t2 <: currentDrive=10;//10|10
                    t2+=halfWidth;
                    break;
                case 5://01|01
                    p @ t2 <: currentDrive=9;//10|01
                    t2+=halfWidth;
                    break;
                }
            }
        }
    }
}


[[combinable]]
 void PWMdrive(unsigned int magRatio, out buffered port:1 p)//ADD: need something to tell test ended
{
    unsigned int currentDrive=0;
    unsigned long int t=0;
    timer tmr;
    tmr :> t;

    while(1)//drives the PWM to control amplitude
    {
        select {
        case tmr when timerafter(t) :> void:
            if (currentDrive==0)
            {
                p @ t <: currentDrive=1;
                t+=magRatio;
            }
            else
            {
                p @ t <: currentDrive=0;
                t+=50-magRatio;
            }
            break;
        }
        //return somehow
    }
}
