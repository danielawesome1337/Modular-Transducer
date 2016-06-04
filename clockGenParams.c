/*
    Daniel Ko
    04/06/2016
    Adapted from http://qrp-labs.com/synth/oe1cgs.html
*/

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

#define F_XTAL 25000000;                        // Frequency of Quartz-Oszillator

int main ()
{
    char checker[2];
    unsigned long frequency;                    // Frequency in Hz; must be within [1MHz to 200Mhz]
    unsigned long fvco;                         // VCO frequency (600-900 MHz) of PLL
    unsigned long divider;                      // Output divider in range [4,6,8-900], even numbers preferred
    uint8_t a;                                  // "a" part of Feedback-Multiplier from XTAL to PLL in range [15,90]
    unsigned long b;                            // "b" part of Feedback-Multiplier from XTAL to PLL
    unsigned long c = 1048574;                  // "c" part of Feedback-Multiplier from XTAL to PLL
    float f;                                    // floating variable, needed in calculation

    FILE *fp;
    fp = fopen("1/parameters.txt", "a+");
    if (fp == NULL)
    {
    	printf("File could not be opened. Exiting.");
        exit(1);
    }
    fscanf(fp, "%*c%ld%*c", &frequency);
    fseek(fp, -2, SEEK_END);
    fscanf(fp, "%s", checker);
    if(checker[0] == '.' && checker[1] == '.')
    {
        printf("File has already been updated. Exiting.");
        exit(2);
    }
    frequency = 50*frequency;

    divider = 900000000 / frequency;        // With 900 MHz beeing the maximum internal PLL-Frequency

    if (divider % 2)
    {
        divider--;                          // finds the even divider which delivers the intended Frequency
    }
    fvco = divider * frequency;             // Calculate the PLL-Frequency (given the even divider)

    a = fvco / F_XTAL;                      // Multiplier to get from Quartz-Oscillator Freq. to PLL-Freq.
    f = fvco - a * F_XTAL;                  // Multiplier = a+b/c
    f = f * c;                              // this is just "int" and "float" mathematics
    f = f / F_XTAL;
    b = f;

    fseek(fp, 0, SEEK_END);
    fprintf(fp, "%d.%ld.%ld.%ld.0.1..", a, b, c, divider);

    fclose(fp);
    return 0;
}
