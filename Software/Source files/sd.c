#include "..\h\sd.h"

#include <xparameters.h>

#include "xsdps.h"
#include "ff.h"


XSdPs SdInstance;
FATFS fsystem;

int sdCardConfig() {
    
    XSdPs_Config *CfgPtr = XSdPs_LookupConfig(XPAR_XSDPS_0_BASEADDR);
    if (!CfgPtr) {
        xil_printf("ERROR: SD config not found\n");
        return XST_FAILURE;
    }

    int status = XSdPs_CfgInitialize(&SdInstance, CfgPtr, CfgPtr->BaseAddress);
    if (status != XST_SUCCESS) {
        xil_printf("ERROR: SD init failed\n");
        return XST_FAILURE;
    }

    FRESULT fresult = f_mount(&fsystem, "0:/", 1);
    if (fresult != FR_OK) {
        xil_printf("ERROR: Failed to mount SD card\n");
        return XST_FAILURE;
    }

    return XST_SUCCESS;
}


int sdReadFile(char* path, u8* buff, u32 size) {
    
    FIL fptr;
    FRESULT fresult;
    UINT bytes;

    fresult = f_open(&fptr, path, FA_READ);
    if (fresult != FR_OK) {
        xil_printf("ERROR: Failed to open a file\n");
        return XST_FAILURE;
    }

    fresult = f_read(&fptr, buff, (UINT)size, &bytes);
    if (fresult != FR_OK) {
        xil_printf("ERROR: Failed to read a file\n");
        f_close(&fptr);
        return XST_FAILURE;
    } else if (bytes < size) {
        xil_printf("ERROR: Insufficient data, wrong image size\n");
        f_close(&fptr);
        return XST_FAILURE;
    }

    f_close(&fptr);
    return XST_SUCCESS;
}


int sdWriteFile(char* path, u8* buff, u32 size) {
    FIL fptr;
    FRESULT fresult;
    UINT bytes;

    fresult = f_open(&fptr, path, FA_CREATE_ALWAYS | FA_WRITE);
    if (fresult != FR_OK) {
        xil_printf("ERROR: Failed to create file\n");
        return XST_FAILURE;
    }

    fresult = f_write(&fptr, buff, (UINT)size, &bytes);
    if (fresult != FR_OK || bytes < size) {
        xil_printf("ERROR: Failed to write a file\n");
        f_close(&fptr);
        return XST_FAILURE;
    } 

    f_close(&fptr);
    return XST_SUCCESS;
}

int sdCardUnmount() {
    FRESULT fresult;

    fresult = f_unmount("0:/");
    if (fresult != FR_OK) {
        xil_printf("ERROR: Failed to unmount SD card\n");
        return XST_FAILURE;
    }

    xil_printf("SD card unmounted successfully\n");
    return XST_SUCCESS;
}