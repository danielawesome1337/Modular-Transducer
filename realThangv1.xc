/*
 * realThangv1.xc
 *
 *  Created on: 10 Mar 2016
 *      Author: Daniel
 */

#include <xs1.h>
#include <stdio.h>
#include <platform.h>
#include <functionDecs.h>

out buffered port:1 ports[7] = {
        XS1_PORT_1A, //D11
        XS1_PORT_1B,
        XS1_PORT_1C,
        XS1_PORT_1D, //D0
        XS1_PORT_1E,
        XS1_PORT_1F,
        XS1_PORT_1G,
};
out buffered port:1 PWM = XS1_PORT_1J;
clock clk = XS1_CLKBLK_1;
clock magClk = XS1_CLKBLK_2;

int main() {
    unsigned int halfWidth = 25, topRatio = 2000000, magRatio = 40;
    int phase[7] = {0,1,2,3,4,5,6};

    //READ IN phase
    //READ IN magRatio
    //READ IN topRatio
    configure_out_port(PWM, magClk, 0);
    for(size_t i = 0; i < 7; i++)
    {
        configure_out_port(ports[i], clk, 0);
    }
    configure_clock_rate(magClk,100,1);
    configure_clock_rate(clk,topRatio,20000);

    start_clock(clk);
    start_clock(magClk);

    par{
        par (size_t i = 0; i < 7; i++)
                    {
            phaseChange(phase[i], halfWidth, ports[i]);
                    }
        magChange(magRatio);
    }

    return 0;
}

void phaseChange(int phase, unsigned int halfWidth, out buffered port:1 p)
{
    unsigned int t = phase;
    while (1)
    {
        t+=halfWidth; p @ t <: 0;
        t+=halfWidth; p @ t <: 1;
    }
}

void magChange(unsigned int magRatio)
{
    unsigned int t = 0;
    while (1)
    {
        t+=magRatio; PWM @ t <: 0;
        t+=50-magRatio; PWM @ t <: 1;
    }
}
