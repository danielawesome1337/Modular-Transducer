/*
 * Pwmtest.xc
 *
 *  Created on: 24 Feb 2016
 *      Author: Daniel
 */


#include <xs1.h>

out port outClock = XS1_PORT_1A;
out buffered port:1 PWM = XS1_PORT_1D; //1D is D2 LED and X0D11
clock    clk      = XS1_CLKBLK_2;

int main() {
    unsigned int t=0;
    unsigned int width=1000;

    configure_port_clock_output(outClock, clk);
    configure_out_port(PWM, clk2, 0);
    set_clock_ref(clk); //reference clock is clk
    set_clock_div(clk, 50); // 1MHz=100MHz/(2*50)
    start_clock(clk);

    while(1)
    {
        t+=width;   PWM @ t <: 0;
        t+=2000-width;  PWM @ t <: 1;
    }
    return 0;
}

