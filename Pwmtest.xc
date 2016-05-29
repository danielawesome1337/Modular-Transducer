/*
 * Pwmtest.xc
 *
 *  Created on: 24 Feb 2016
 *      Author: Daniel
 */


#include <xs1.h>
#include <stdio.h>

clock clk = XS1_CLKBLK_1;
out buffered port:1 servo = XS1_PORT_1F;

int main(void)
{
    int i;
    unsigned int t=0;
    unsigned int width=1500;

    configure_out_port(servo, clk, 0);
    set_clock_ref(clk);
    set_clock_div(clk, 50); // 1MHz
    start_clock(clk);

    while(1)
    {
        printf("Enter servo position in microseconds (1500 is center):\n");
        scanf("%d", &width);
        for (i=0; i<200; i++) // loop for a while
        {
            t+=width;   servo @ t <: 0;
            t+=20000-width;  servo @ t <: 1;
        }
        t+=width;   servo @ t <: 0;
    }

    return 0; // warning on this line is ok
}
