#include "..\h\dma.h"

#include <stdio.h>
#include <xil_cache.h>
#include <xparameters.h>

#include "xaxidma.h"
#include "xinterrupt_wrap.h"

#define DMA_TRANSFER_TIMEOUT 100000

XAxiDma AxiDma;
XAxiDma_Config *AxiDmaConfigPtr;

volatile u32 txDone = 0;
volatile u32 rxDone = 0;

#define CACHE_LINE_SIZE 32U

static inline u32 round_up_to_cacheline(u32 n)
{
    return (n + CACHE_LINE_SIZE - 1U) & ~(CACHE_LINE_SIZE - 1U);
}

void txIntrHandler(void *callback) 
{
	u32 IrqStatus;
	XAxiDma *AxiDmaInst = (XAxiDma*) callback;

	// Read pending interrupts
	IrqStatus = XAxiDma_IntrGetIrq(AxiDmaInst, XAXIDMA_DMA_TO_DEVICE);

	// Acknowledge pending interrupts
	XAxiDma_IntrAckIrq(AxiDmaInst, IrqStatus, XAXIDMA_DMA_TO_DEVICE);

	// Set TX done only if transmit chain is completed
	if ((IrqStatus & XAXIDMA_IRQ_IOC_MASK)) {
		txDone = 1;
	}

    return;
}

void rxIntrHandler(void *callback) 
{
	u32 IrqStatus;
	XAxiDma *AxiDmaInst = (XAxiDma*) callback;

	// Read pending interrupts
	IrqStatus = XAxiDma_IntrGetIrq(AxiDmaInst, XAXIDMA_DEVICE_TO_DMA);

	// Acknowledge pending interrupts
	XAxiDma_IntrAckIrq(AxiDmaInst, IrqStatus, XAXIDMA_DEVICE_TO_DMA);

	// Set RX done only if receive chain is completed
	if ((IrqStatus & XAXIDMA_IRQ_IOC_MASK)) {
		rxDone = 1;
	}

    return;
}


int dmaConfig() 
{
    int status;
    
    // DMA configuration
    AxiDmaConfigPtr = XAxiDma_LookupConfig(XPAR_XAXIDMA_0_BASEADDR);
	if (!AxiDmaConfigPtr) {
		printf("ERROR: No configuration found for DMA %d\n", XPAR_XAXIDMA_0_BASEADDR);
		return XST_FAILURE;
	}

	status = XAxiDma_CfgInitialize(&AxiDma, AxiDmaConfigPtr);
	if (status != XST_SUCCESS) {
		printf("ERROR: DMA initialization failed %d\n", status);
		return XST_FAILURE;
	}

	if (XAxiDma_HasSg(&AxiDma)) {
		printf("ERROR: DMA configure in SG mode\n");
		return XST_FAILURE;
	}

	// Configure DMA interrupts
	status = XSetupInterruptSystem(&AxiDma, &txIntrHandler,
				                  AxiDmaConfigPtr->IntrId[0], AxiDmaConfigPtr->IntrParent,
				                  XINTERRUPT_DEFAULT_PRIORITY);
	if (status != XST_SUCCESS) {
        printf("ERROR: Cannot configure DMA TX interrupt\n");
		return XST_FAILURE;
	}

	status = XSetupInterruptSystem(&AxiDma, &rxIntrHandler,
				                   AxiDmaConfigPtr->IntrId[1], AxiDmaConfigPtr->IntrParent,
				                   XINTERRUPT_DEFAULT_PRIORITY);
	if (status != XST_SUCCESS) {
        printf("ERROR: Cannot configure DMA RX interrupt\n");
		return XST_FAILURE;
	}

    return XST_SUCCESS;
}

void dmaReset()
{
    XAxiDma_Reset(&AxiDma);
    while (!XAxiDma_ResetIsDone(&AxiDma));
}

int dmaStartTransfers(u8* txBuff, u32 txSize, u8* rxBuff, u32 rxSize) 
{
    int status;

    // Enable TX and RX interrupts
    XAxiDma_IntrEnable(&AxiDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);
	XAxiDma_IntrEnable(&AxiDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);

    u32 txSz = round_up_to_cacheline(txSize);
    u32 rxSz = round_up_to_cacheline(rxSize);

    // TX: CPU->DMA
    Xil_DCacheFlushRange((UINTPTR)txBuff, txSz);

    // RX: DMA->CPU
    Xil_DCacheInvalidateRange((UINTPTR)rxBuff, rxSz);


	// Start DMA tranfers
	status = XAxiDma_SimpleTransfer(&AxiDma, (UINTPTR) rxBuff, 
                                    rxSize, XAXIDMA_DEVICE_TO_DMA);

	if (status != XST_SUCCESS) {
        printf("ERROR: Starting RX DMA failed %d\n", status);
        return XST_FAILURE;
	}

	status = XAxiDma_SimpleTransfer(&AxiDma, (UINTPTR) txBuff, 
                                    txSize, XAXIDMA_DMA_TO_DEVICE);
	if (status != XST_SUCCESS) {
        printf("ERROR: Starting TX DMA failed %d\n", status);
		return XST_FAILURE;
	}

    return XST_SUCCESS;
}

int dmaWaitTransfers(u32 txSize, u32 rxSize) 
{
    int status;

    // Wait for TX done or timeout
	status = Xil_WaitForEventSet(DMA_TRANSFER_TIMEOUT, 1, &txDone);
	if (status != XST_SUCCESS) {
		printf("ERROR: Transmit failed %d\n", status);
		return XST_FAILURE;
	}
    printf("Transmit done\n");

	// Wait for RX done or timeout
	status = Xil_WaitForEventSet(DMA_TRANSFER_TIMEOUT, 1, &rxDone);
	if (status != XST_SUCCESS) {
		printf("ERROR: Receive failed %d\n", status);
		return XST_FAILURE;
	}
    printf("Receive done\n");

    Xil_DCacheInvalidateRange( round_up_to_cacheline(txSize),  round_up_to_cacheline(rxSize));

    // Disable TX and RX interrupts
	XDisconnectInterruptCntrl(AxiDmaConfigPtr->IntrId[0], AxiDmaConfigPtr->IntrParent);
	XDisconnectInterruptCntrl(AxiDmaConfigPtr->IntrId[1], AxiDmaConfigPtr->IntrParent);

    return XST_SUCCESS;
}