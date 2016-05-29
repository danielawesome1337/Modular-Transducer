/*
 * 5mhzTest.xc
 *
 *  Created on: 20 May 2016
 *      Author: Daniel
 */

#include <xs1.h>
#include <stdio.h>
#include <platform.h>
#include <functionDecs.h>
#include <timer.h>
#include <print.h>

//1 1 bit port for the push/pull output for 1 transducer
out buffered port:1 PP = XS1_PORT_1A;

//2 1 bit ports for the PWM output for 1 transducer
out buffered port:1 PWM1 = XS1_PORT_1C;
out buffered port:1 PWM2 = XS1_PORT_1D;

//clock declarations
clock PPclk = XS1_CLKBLK_1;//push/pull clock
clock PWMclk = XS1_CLKBLK_2;//PWM clock

int main() {
    while(1)
    {
        //halfWidth is the length of the on period = off period of push/pull (50 ticks per wavelength)
        unsigned int halfWidth = 10;

        //magRatio is the PWM on period out of 50
        unsigned int magRatio1 = 45;
        unsigned int magRatio2= 23;

        //link 2 bit ports to push/pull clock. Initial out = 0
        configure_out_port(PP, PPclk, 0);

        //link 1 bit ports to PWM clock. Initial out = 0
        configure_out_port(PWM1, PWMclk, 0);
        configure_out_port(PWM2, PWMclk, 0);

        configure_clock_rate_at_least(PPclk,1000,10);//1000/10=100MHz
        configure_clock_rate_at_least(PWMclk,1000,20);//2MHz at 50 tick wavelength

        start_clock(PPclk);
        start_clock(PWMclk);

        while(1)
        {
            /*STUFF HAPPENS NOW*/
            par
            {
                [[combine]]
                 par
                 {
                    PWMdrive(magRatio1, PWM1);
                    PWMdrive(magRatio2, PWM2);
                 }
                freqDrive(halfWidth, PP);
            }
        }
    }
    return 0;
}

void freqDrive(unsigned int halfWidth, out buffered port:1 p)
{
    unsigned long int t=200;
    unsigned int currentDrive = 0;//0 Binary
    while(1)
    {
        switch(currentDrive)
        {
        case 0://0
            p @ t <: currentDrive=1;//1
            t+=halfWidth;
            break;
        case 1://1
            p @ t <: currentDrive=0;//0
            t+=halfWidth;
            break;
        }
    }
}

[[combinable]]
 void PWMdrive(unsigned int magRatio, out buffered port:1 p)
{
    unsigned int t = 20;
    unsigned int magRatioInverse = 50 - magRatio;
    unsigned int currentDrive=0;
    timer tmr;

    while(1)//drives the PWM to control amplitude
    {
        select {
        case tmr when timerafter(0) :> void:
            if (currentDrive==0 && magRatio!=0)
            {
                p @ t <: currentDrive=1;
                t+=magRatio;
            }
            else if(magRatio!=50)
            {
                p @ t <: currentDrive=0;
                t+=magRatioInverse;
            }
            break;
        }
    }
}
