#include "..\h\timer.h"

#include <xparameters.h>
#include "xtmrctr.h"

#define TMR_CNT_0 0

XTmrCtr AxiTimerInst;

int timerConfig() 
{
    int status = XST_FAILURE;

    status = XTmrCtr_Initialize(&AxiTimerInst, XPAR_AXI_TIMER_0_BASEADDR);
    if (status != XST_SUCCESS) return XST_FAILURE;

    XTmrCtr_SetResetValue(&AxiTimerInst, TMR_CNT_0, 0);
    XTmrCtr_SetOptions(&AxiTimerInst, TMR_CNT_0, XTC_AUTO_RELOAD_OPTION);

    return XST_SUCCESS;
}

void startTimer() 
{
    XTmrCtr_Start(&AxiTimerInst, TMR_CNT_0);
}

void stopTimer() 
{
    XTmrCtr_Stop(&AxiTimerInst, TMR_CNT_0);
}

void resetTimer() 
{
    XTmrCtr_Reset(&AxiTimerInst, TMR_CNT_0);
}

long double getTime() 
{
    return (long double) XTmrCtr_GetValue(&AxiTimerInst, TMR_CNT_0) / XPAR_AXI_TIMER_0_CLOCK_FREQUENCY * 1000000;
}
