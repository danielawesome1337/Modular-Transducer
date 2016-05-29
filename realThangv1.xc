/*
 * realThangv2.xc
 *
 *  Created on: 11 Mar 2016
 *      Author: dsdan
 */


#include <xs1.h>
#include <stdio.h>
#include <platform.h>
#include <functionDecs.h>

out buffered port:4 ports[6] = {
        XS1_PORT_4A,
        XS1_PORT_4B,
        XS1_PORT_4C,
        XS1_PORT_4D,
        XS1_PORT_4E,
        XS1_PORT_4F,
};//only 6 4 bit ports in startKIT

//clock declarations
clock clk = XS1_CLKBLK_1;//push/pull clock
clock PRFclk = XS1_CLKBLK_2;//pulse repetition frequency clock

int main() {
    //topRatio is the exact frequency of the push/pull (200000 = 200kHz)
    //pulseNumber is the number of pulses per test
    //PRF is the pulse repetition frequency
    unsigned long int topRatio = 400000; //,pulseNumber = 1000, PRF = 1000;

    //halfWidth is the length of the on period = off period of the push/pull (50 ticks per wavelength)
    //magRatio is the PWM on period out of 50
    //magRatio should be a matrix for every pulse in a set of pulses
    //pulseLength is the length of each pulse in units of wavelengths
    unsigned int halfWidth = 25, magRatio = 7; //,pulseLength=10;

    //phase is the matrix of how many ticks each port is out of phase where 0 is no shift
    unsigned int phase[6] = {0,1,2,3,4,5};

    //link 4 bit ports to push/pull clock. Initial out = 0
    for(size_t i = 0; i < 6; i++)
    {
        configure_out_port(ports[i], clk, 0);
    }

    while(1)
    {
        //READ IN topRatio.
        //READ IN pulseNumber.
        //READ IN PRF.
        //READ IN magRatio.
        //READ IN pulseLength
        //READ IN phase.

        configure_clock_rate_at_least(clk,topRatio,20000);//1000000/50=20000 so 50 tick wavelength
        //configure_clock_rate_at_least(PRFclk,PRF,20000);

        while(1)//for(size_t i = 0; i < pulseNumber; i++)
        {
            start_clock(PRFclk);
            //@ PRFclk whatever
            start_clock(clk);

            par (size_t i = 0; i < 6; i++)
            {
                phaseMag(phase[i], halfWidth, magRatio, ports[i]);
            }
            stop_clock(clk);
        }
    }
    return 0;
}

void phaseMag(unsigned int phase, unsigned int halfWidth,
        unsigned int magRatio, out buffered port:4 p)//pulseLength
{
    //4 bits per port. 1st bit is PWM, 2nd bit is push and 3rd bit is pull
    //maybe hard code numbers instead of count+-= to increase speed?
    unsigned int tF = 100+phase;//delay in push/pull start
    unsigned int tM = 0;//start PWM immediately
    unsigned int count = 5;//0101
    while (1)//pulseLength not 1
    {
        if(tM<tF)//if PWM to flip next
        {
            switch(count)
            {
            case 5://0101
                p @ tM <: count=4;//0110 OR 0010
                tM+=10-magRatio;
                break;
            case 4:
                p @ tM <: count=5;//0110 OR 0010
                tM+=magRatio;
                break;
            case 3:
                p @ tM <: count=2;//0110 OR 0010
                tM+=10-magRatio;
                break;
            case 2:
                p @ tM <: count=3;//0110 OR 0010
                tM+=magRatio;
                break;
            }
        }
        if(tM>tF)//if push/pull to flip next
        {
            switch(count)
            {
            case 5://0101
                p @ tF <: count=3;//0011 OR 0010
                tF+=halfWidth;
                break;
            case 4://0100
                p @ tF <: count=2;//0011 OR 0010
                tF+=halfWidth;
                break;
            case 3://0100
                p @ tF <: count=5;//0011 OR 0010
                tF+=halfWidth;
                break;
            case 2://0100
                p @ tF <: count=4;//0011 OR 0010
                tF+=halfWidth;
                break;
            }
        }
        else if(tM==tF)//if PWM and push/pull flip at the same time
        {
            switch(count)
            {
            case 5://0101
                p @ tF <: count=2;//0010
                tF+=halfWidth;
                tM+=10-magRatio;
                break;
            case 4://0100
                p @ tF <: count=3;//0011
                tF+=halfWidth;
                tM+=magRatio;
                break;
            case 3://0011
                p @ tF <: count=4;//0100
                tF+=halfWidth;
                tM+=10-magRatio;
                break;
            case 2://0010
                p @ tF <: count=5;//0101
                tF+=halfWidth;
                tM+=magRatio;
                break;
            }
        }
    }
}
