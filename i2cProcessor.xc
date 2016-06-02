/*
 * i2cProcessor.xc
 *
 *  Created on: 2 Jun 2016
 *      Author: dsdan
 */

#ifndef SYS_HEADERS
#define SYS_HEADERS
#include <xs1.h> //essential
#include <platform.h> //essential
#include <i2c.h> //i2c
#include <stdlib.h> //exiting
#include <stdio.h> //reading from console
#include <print.h> //writing to console and debugging
#include <math.h> //rounding
#endif

#include <AdafruitTranslation.h>

void clockSet(client i2c_master_if i2c) {
    Adafruit_SI5351 ada;
    if (Adafruit_SI5351Config(ada) != ERROR_NONE)
    {
        printstrln("Something's broke fam");
        exit(1);
    }
    begin(i2c, ada);
    setupPLLInt(i2c, ada, SI5351_PLL_A, 36);
    setupMultisynthInt(i2c, ada, 0, SI5351_PLL_A, SI5351_MULTISYNTH_DIV_8);
    enableOutputs(i2c, ada, true);
}

port p_scl = XS1_PORT_4C;
port p_sda = XS1_PORT_1G;

int main(void) {
    i2c_master_if i2c[1];

    par {
        i2c_master(i2c, 1, p_scl, p_sda, 100);
        clockSet(i2c[0]);
    }
    return 0;
}
