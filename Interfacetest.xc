/*
 * Interfacetest.xc
 *
 *  Created on: 20 Feb 2016
 *      Author: Daniel
 */

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
interface my_interface {
    void fA(int x, int y);
    void fB(float x);
};

void task1(interface my_interface client c)
{
    c.fA(5, 10);
}
void task2(interface my_interface server c)
{
    // wait for either fA or fB over connection c.
    select {
    case c.fA(int x, int y):
            printf("Received fA: %d, %d\n", x, y);
            break;
    case c.fB(float x):
        // handle the message
        printf("Received fB: %f\n", x);
        break;
    }
}

int main(void)
{
    interface my_interface c;
    par {
        on tile[0]:task1(c);
        on tile[0]:task2(c);
    }
    return 0;
}
