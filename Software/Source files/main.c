#include <stdio.h>
#include <stdlib.h>
#include <xstatus.h>

#include "xil_util.h"
#include "..\h\dma.h"
#include "..\h\params.h"
#include "..\h\processing.h"
#include "..\h\sd.h"
#include "..\h\timer.h"

// Helper functions

int hwConfig();                                                             // Hardware configuration
int selectOption();                                                         // User interraction
int safeScanInt(int min, int max);                                          // Safe integer reading from input
int addImage(u8** imBuff, u8** swBuff, u8** hwBuff, Params_t* params);      // Adding an image from SD card
int saveProcessedImages(u8* swBuff, u8* hwBuff, Params_t params);           // Save an image on SD card
void printParams(Params_t params);                                          // Prints current parameter values
void freeMemory(u8** imBuff, u8** swBuff, u8** hwBuff);                     // Frees memory if it is allocated for the buffers

int main(void)
{
    int status = XST_FAILURE;
    Params_t params = {0, 0, 30, EDGE, CLOSEST_ELEM, NO, ".bin"};
    u8* imBuff = NULL;
    u8* swBuff = NULL;
    u8* hwBuff = NULL;

    printf("\n --- IMAGE EDGE DETECTION --- \n\n");
    
    // Configure hardware (DMA, Timer, SD card)
    status = hwConfig();
    if (status != XST_SUCCESS) {
        printf("ERROR: Hardware configuration failed\n");
        return XST_FAILURE;
    }
    printf("Hardware configuration done\n");

    // Main program loop (selecting option)
    for (;;) { 
        int option = selectOption();

        switch (option) {
        case 1:
            status = addImage(&imBuff, &swBuff, &hwBuff, &params);
            if (status != XST_SUCCESS) {
                printf("ERROR: Failed to add image\n");
                continue;
            }
            printf("Image added\n");
            break;
        case 2:
            if (imBuff == NULL || swBuff == NULL || hwBuff == NULL) {
                printf("ERROR: First add an image\n");
                continue;
            }

            status = processing(imBuff, swBuff, hwBuff, params);
            if (status != XST_SUCCESS) {
                printf("ERROR: Accelerator processing failed\n");
                continue;
            }
            printf("\nAccelerator processing done\n\n");

            status = saveProcessedImages(swBuff, hwBuff, params);
            if (status != XST_SUCCESS) {
                printf("ERROR: Saving processed images failed\n");
                continue;
            }
            printf("Processed images saved\n");
            break;
        case 3:
            printf("Select mode (Edge = 0, GradH = 1, GradV = 2, GradM = 3): "); 
            params.Mode = (Mode_t) safeScanInt(0, 3);
            printf("Mode selected\n");
            break;
        case 4:
            printf("Edge threshold: ");
            params.EdgeThr = (u16) safeScanInt(0, 255);
            printf("Edge threshold set\n");
            break;
        case 5:
            printf("Border parameter (Zero = 0, ClosestElem = 1): ");
            params.Border = (Border_t) safeScanInt(0, 1);
            printf("Border parameter set\n");
            break;
        case 6:
            printf("Bypass processing (NO = 0, YES = 1): ");
            params.Bypass = (Bypass_t) safeScanInt(0, 1);
            printf("Bypass parameter set\n");
            break;
        case 7:
            printParams(params);
            break;
        case 8:
            freeMemory(&imBuff, &swBuff, &hwBuff);
            printf("Image deleted\n");
            break;
        case 0:
            freeMemory(&imBuff, &swBuff, &hwBuff);
            sdCardUnmount();
            printf("\nGoodbye :)\n");
            exit(XST_SUCCESS);
            break;
        default:
            print("ERROR: Invalid option\n");
            continue;
        }
    }
}

// Helper functions

int hwConfig() 
{
    int status = XST_FAILURE;

    // SD configuration
    status = sdCardConfig();
    if (status != XST_SUCCESS) {
        printf("ERROR: SD card configuration failed\n");
        return XST_FAILURE;        
    }
    printf("SD card configuration done\n");

    // Timer configuration
    status = timerConfig();
    if (status != XST_SUCCESS) {
        printf("ERROR: Timer configuration failed\n");
        return XST_FAILURE;
    }
    printf("Timer configuration done\n");

    // DMA configuration
    status = dmaConfig();
    if (status != XST_SUCCESS) {
        printf("ERROR: DMA configuration failed\n");
        return XST_FAILURE;        
    }
    printf("DMA configuration done\n");

    return XST_SUCCESS;
}

int selectOption()
{
    int option = 0;

    printf("\n-----------------------------------------\n\n");
    printf("Options:\n\n");
    printf("1. Add image\n");
    printf("2. Process image\n");
    printf("3. Select mode\n");
    printf("4. Change edge threshold\n");
    printf("5. Change border parameter\n");
    printf("6. Bypass processing\n");
    printf("7. Print current parameters\n");
    printf("8. Delete image (free memory)\n");
    printf("0. Exit program\n");
    
    printf("\nSelect option: ");
    scanf("%d", &option);
    printf("\n\n-----------------------------------------\n\n");
    
    return option;
}

int safeScanInt(int min, int max) {
    int value;
    int c;

    while (1) {
        if (scanf("%d", &value) == 1) {
            printf("\n");
            while ((c = getchar()) != '\n' && c != EOF) {}
            
            if (value >= min && value <= max) {
                return value;
            } else {
                printf("Out of range! Please enter [%d - %d]", min, max);
            }
            
        } else {
            printf("\nInvalid input! Please enter an integer\n");
            while ((c = getchar()) != '\n' && c != EOF) {}
        }
    }
}

int addImage(u8** imBuff, u8** swBuff, u8** hwBuff, Params_t* params) {
    if (*imBuff != NULL || *swBuff != NULL || *hwBuff != NULL) {
        printf("ERROR: The image has already been added, first delete the previous image\n");
        return XST_FAILURE;
    }

    // Image file name
    char format[16];
    snprintf(format, sizeof(format), "%%%ds", MAX_FILENAME_LEN);
    printf("Enter image file name: "); scanf(format, params->ImgName); printf("\n");

    // Image dimensions
    printf("Image width: ");
    params->ImgW = (u16) safeScanInt(4, MAX_IMG_DIMENSION);

    printf("Image height: ");
    params->ImgH = (u16) safeScanInt(4, MAX_IMG_DIMENSION);

    u32 imgSize = params->ImgW * params->ImgH;

    // Buffers allocation
    printf("\nBuffer addresses:\n");

    // Image buffer
    *imBuff = (u8*) malloc(imgSize);
    xil_printf("Image buffer address -> %x \n", *imBuff);
	
    // Software buffer
    *swBuff = (u8*) malloc(imgSize);
    xil_printf("Software buffer address -> %x \n", *swBuff);

    // Hardware buffer
    *hwBuff = (u8*) malloc(imgSize);
    xil_printf("Hardware buffer address -> %x \n\n", *hwBuff);

    if (*imBuff == NULL || *swBuff == NULL || *hwBuff == NULL) {
        printf("ERROR: Memory allocation failed\n");
        freeMemory(imBuff, swBuff, hwBuff);
        return XST_FAILURE;
    }

    // Read image file
    char path[MAX_PATH_LEN+1]; 
    snprintf(path, sizeof(path), "0:/images/%s.bin", params->ImgName);

    int status = sdReadFile(path, *imBuff, imgSize);
    if (status != XST_SUCCESS) {
        printf("ERROR: File reading failed\n");
        freeMemory(imBuff, swBuff, hwBuff);
        return XST_FAILURE;
    }

    return XST_SUCCESS;
}
    

int saveProcessedImages(u8 *swBuff, u8 *hwBuff, Params_t params) 
{
    char path[MAX_PATH_LEN+1];
    char fileName[MAX_FILENAME_LEN+1];
    u32 imgSize = params.ImgW * params.ImgH;

    switch (params.Bypass) {
    case YES:
        snprintf(fileName, sizeof(fileName), "%s_bypass", params.ImgName);
        break;
    case NO:
        switch (params.Mode) {
        case GRAD_H:
            snprintf(fileName, sizeof(fileName), "%s_gradH", params.ImgName);
            break;
        case GRAD_V:
            snprintf(fileName, sizeof(fileName), "%s_gradV", params.ImgName);
            break;
        case GRAD_M:
            snprintf(fileName, sizeof(fileName), "%s_gradM", params.ImgName);
            break;
        case EDGE:
            snprintf(fileName, sizeof(fileName), "%s_edge%d", params.ImgName, params.EdgeThr);
            break;
        }

        switch (params.Border) {
        case ZERO:
            strncat(fileName, "_b0", sizeof(fileName) - strlen(fileName) - 1);
            break;
        case CLOSEST_ELEM:
            strncat(fileName, "_b1", sizeof(fileName) - strlen(fileName) - 1);
            break;
        }
        break;
    }
    
    // Write software version into file
    snprintf(path, sizeof(path), "0:/processed/%s_sw.bin", fileName);

    int status = sdWriteFile(path, swBuff, imgSize);
    if (status != XST_SUCCESS) {
        printf("ERROR: File writing failed\n");
        return XST_FAILURE;
    }

    // Write hardware version into file
    snprintf(path, sizeof(path), "0:/processed/%s_hw.bin", fileName);

    status = sdWriteFile(path, hwBuff, imgSize);
    if (status != XST_SUCCESS) {
        printf("ERROR: File writing failed\n");
        return XST_FAILURE;
    }

    return XST_SUCCESS;
}

void printParams(Params_t params)
{
    printf("Current parameters:\n");
    printf("Image width = %hu\n", params.ImgW);
    printf("Image height = %hu\n", params.ImgH);
    printf("Edge threshold = %hu\n", params.EdgeThr);
    
    switch (params.Mode) {
    case GRAD_H:
        printf("Current mode: Horizontal gradient\n");
        break;
    case GRAD_V:
        printf("Current mode: Vertical gradient\n");
        break;
    case GRAD_M:
        printf("Current mode: Magnitude gradient\n");
        break;            
    case EDGE:
        printf("Current mode: Edge detection\n");
        break;
    }

    switch (params.Border) {
    case ZERO:
        printf("Border option: Zero\n");
        break;
    case CLOSEST_ELEM:
        printf("Border option: Closest element\n");
        break;
    }
    
    switch (params.Bypass) {
    case NO:
        printf("Bypass: NO\n");
        break;
    case YES:
        printf("Bypass: YES\n");
        break;
    }
}


void freeMemory(u8 **imBuff, u8 **swBuff, u8 **hwBuff) 
{
    if (*imBuff) {
        free(*imBuff); 
        *imBuff = NULL;
    }
    if (*swBuff) {
        free(*swBuff); 
        *swBuff = NULL;
    }
    if (*hwBuff) {
        free(*hwBuff); 
        *hwBuff = NULL;
    } 

    printf("Memory freed\n");
}