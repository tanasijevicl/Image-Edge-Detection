#include "..\h\processing.h"

#include <stdio.h>
#include <stdlib.h>
#include <xil_cache.h>
#include <xparameters.h>
#include <xstatus.h>

#include "..\h\dma.h"
#include "..\h\sd.h"
#include "..\h\timer.h"

#define REG_CTRL_ADDR        0
#define REG_EDGE_THR_ADDR    4
#define REG_IMG_W_ADDR       8
#define REG_IMG_H_ADDR       12

// Helper functions

int accConfig(Params_t params)
{
    u16 reg_ctrl = 0;
    reg_ctrl = (params.Border << 3) | (params.Bypass << 2) | params.Mode;

    // Configure accelerator parameters
    Xil_Out32(XPAR_AXI_ACC_EDGE_DETECTION_0_BASEADDR + REG_IMG_H_ADDR, params.ImgH);
    Xil_Out32(XPAR_AXI_ACC_EDGE_DETECTION_0_BASEADDR + REG_IMG_W_ADDR, params.ImgW);
    Xil_Out32(XPAR_AXI_ACC_EDGE_DETECTION_0_BASEADDR + REG_CTRL_ADDR, reg_ctrl);
    Xil_Out32(XPAR_AXI_ACC_EDGE_DETECTION_0_BASEADDR + REG_EDGE_THR_ADDR, params.EdgeThr);

    if (Xil_In32(XPAR_AXI_ACC_EDGE_DETECTION_0_BASEADDR + REG_IMG_H_ADDR) != params.ImgH) return XST_FAILURE;
    if (Xil_In32(XPAR_AXI_ACC_EDGE_DETECTION_0_BASEADDR + REG_IMG_W_ADDR) != params.ImgW) return XST_FAILURE;
    if (Xil_In32(XPAR_AXI_ACC_EDGE_DETECTION_0_BASEADDR + REG_CTRL_ADDR) != reg_ctrl) return XST_FAILURE;
    if (Xil_In32(XPAR_AXI_ACC_EDGE_DETECTION_0_BASEADDR + REG_EDGE_THR_ADDR) != params.EdgeThr) return XST_FAILURE;

    return XST_SUCCESS;
}

void gradHcalc(u8* imBuff, s8* gradH, Params_t params, int r, int c) 
{
    if (c == 0) {
        switch (params.Border) {
        case ZERO:
            gradH[r*params.ImgW + c] = (imBuff[r*params.ImgW + (c+1)] - 0) / 2;
            break;
        case CLOSEST_ELEM:
            gradH[r*params.ImgW + c] = (imBuff[r*params.ImgW + (c+1)] - imBuff[r*params.ImgW + (c)]) / 2;
            break;
        }
    } 
    else if (c == params.ImgW - 1) {
        switch (params.Border) {
        case ZERO:
            gradH[r*params.ImgW + c] = (0 - imBuff[r*params.ImgW + (c-1)]) / 2;
            break;
        case CLOSEST_ELEM:
            gradH[r*params.ImgW + c] = (imBuff[r*params.ImgW + (c)] - imBuff[r*params.ImgW + (c-1)]) / 2;
            break;
        } 
    } 
    else {
        gradH[r*params.ImgW + c] = (imBuff[r*params.ImgW + (c+1)] - imBuff[r*params.ImgW + (c-1)]) / 2;
    }

    return;
}

void gradVcalc(u8* imBuff, s8* gradV, Params_t params, int r, int c) 
{
    if (r == 0) {
        switch (params.Border) {
        case ZERO:
            gradV[r*params.ImgW + c] = (imBuff[(r+1)*params.ImgW + c] - 0) / 2;
            break;
        case CLOSEST_ELEM:
            gradV[r*params.ImgW + c] = (imBuff[(r+1)*params.ImgW + c] - imBuff[r*params.ImgW + c]) / 2;
            break;
        }
    } 
    else if (r == params.ImgH - 1) {
        switch (params.Border) {
        case ZERO:
            gradV[r*params.ImgW + c] = (0 - imBuff[(r-1)*params.ImgW + c]) / 2;
            break;
        case CLOSEST_ELEM:
            gradV[r*params.ImgW + c] = (imBuff[r*params.ImgW + c] - imBuff[(r-1)*params.ImgW + c]) / 2;
            break;
        } 
    } 
    else {
        gradV[r*params.ImgW + c] = (imBuff[(r+1)*params.ImgW + c] - imBuff[(r-1)*params.ImgW + c]) / 2;
    }
    
    return;
}

void swProcessing(u8* imBuff, u8* swBuff, Params_t params) 
{   
    int r, c;
    int imageSize = params.ImgH * params.ImgW;

    s8 gradH[imageSize];
    s8 gradV[imageSize];
    u8 gradM[imageSize];

    switch (params.Bypass) {
    case YES:
        for (r = 0; r < params.ImgH; r++) {
            for (c = 0; c < params.ImgW; c++) {
                swBuff[r*params.ImgW + c] = imBuff[r*params.ImgW + c];
            }
        }
    break;
    case NO:
        switch (params.Mode) {
        case GRAD_H:
            for (r = 0; r < params.ImgH; r++) {
                for (c = 0; c < params.ImgW; c++) {
                    gradHcalc(imBuff, gradH, params, r, c);
                    swBuff[r*params.ImgW + c] = gradH[r*params.ImgW + c];
                }
            }
            break;
        case GRAD_V:
            for (r = 0; r < params.ImgH; r++) {
                for (c = 0; c < params.ImgW; c++) {
                    gradVcalc(imBuff, gradV, params, r, c);
                    swBuff[r*params.ImgW + c] = gradV[r*params.ImgW + c];
                }
            }
            break;
        case GRAD_M:
            for (r = 0; r < params.ImgH; r++) {
                for (c = 0; c < params.ImgW; c++) {
                    gradHcalc(imBuff, gradH, params, r, c);
                    gradVcalc(imBuff, gradV, params, r, c);
                    swBuff[r*params.ImgW + c] = abs(gradH[r*params.ImgW + c]) + abs(gradV[r*params.ImgW + c]);
                }
            }
            break;
        case EDGE:
            for (r = 0; r < params.ImgH; r++) {
                for (c = 0; c < params.ImgW; c++) {
                    gradHcalc(imBuff, gradH, params, r, c);
                    gradVcalc(imBuff, gradV, params, r, c);
                    gradM[r*params.ImgW + c] = abs(gradH[r*params.ImgW + c]) + abs(gradV[r*params.ImgW + c]);
                    swBuff[r*params.ImgW + c] = (gradM[r*params.ImgW + c] < params.EdgeThr) ? 0 : 255;
                }
            }
            break;
        }
    break;
    }
    return;
}

int hwProcessing(u8* imBuff, u8* hwBuff, Params_t params) 
{   
    int status = XST_FAILURE;
    int imageSize = params.ImgH * params.ImgW;

    dmaReset();

    status = dmaStartTransfers(imBuff, imageSize, hwBuff, imageSize);
    if (status != XST_SUCCESS) {
        printf("ERROR: Starting DMA transfers failed\n");
        return XST_FAILURE;        
    }

    status = dmaWaitTransfers(imageSize, imageSize);
    if (status != XST_SUCCESS) {
        printf("ERROR: Completing DMA transfers failed\n");
        return XST_FAILURE;        
    }

    return XST_SUCCESS;
}

int checkData(u8* hwBuff, u8* swBuff, Params_t params) 
{
	int r = 0;
    int c = 0;
    int imageSize = params.ImgH * params.ImgW;
    int status = XST_SUCCESS;

	// Invalidate RxBuffer to force read newest values from DDR
	Xil_DCacheInvalidateRange((UINTPTR)hwBuff, imageSize*sizeof(hwBuff[0]));

    for (r = 0; r < params.ImgH; r++) {
        for (c = 0; c < params.ImgW; c++) {             
            if (hwBuff[r*params.ImgW + c] != swBuff[r*params.ImgW + c]) {
			    printf("DATA CHECK ERROR: Row: %3d Column: %3d Received output %3d instead of %3d\n", r, c, hwBuff[r*params.ImgW + c], swBuff[r*params.ImgW + c]);
                status = XST_FAILURE;
		    }
        }
    }

	return status;
}

// Processing function

int processing(u8* imBuff, u8* swBuff, u8* hwBuff, Params_t params) 
{
    int status = XST_FAILURE;
    long double swTime = 0;
    long double hwTime = 0;

    // Software processing
    printf("\nSoftware processing started\n");
    startTimer();
    swProcessing(imBuff, swBuff, params);
    stopTimer();
    swTime = getTime();
    resetTimer();
    printf("Referent data generated, time: %.0Lf us\n", swTime);

    // Image edge detection accelerator configuration
    status = accConfig(params);
    if (status != XST_SUCCESS) {
        printf("ERROR: Accelerator configuration failed\n");
        return XST_FAILURE;
    }
    printf("Accelerator configuration done\n");

    // Hardware processing
    printf("\nHardware processing started\n");
    startTimer();
    status = hwProcessing(imBuff, hwBuff, params);
    stopTimer();
    if (status != XST_SUCCESS) {
        printf("ERROR: Hardware processing failed\n");
        return XST_FAILURE;
    }
    hwTime = getTime();
    resetTimer();
    printf("Hardware processing completed, time: %.0Lf us\n", hwTime);
    
    printf("\nHardware acceleration: %.0Lf us (%.2Lfx)\n", swTime - hwTime, swTime/hwTime);

    // Check data
    status = checkData(hwBuff, swBuff, params);
    if (status != XST_SUCCESS) {
        printf("\nERROR: Data check failed");
    } else {
        printf("\nData check OK");
    }

    return XST_SUCCESS;
}
