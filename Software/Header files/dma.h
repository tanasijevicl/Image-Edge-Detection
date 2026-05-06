#ifndef DMA_H
#define DMA_H

#include "xil_util.h"

int dmaConfig();
void dmaReset();
int dmaStartTransfers(u8* txBuff, u32 txSize, u8* rxBuff, u32 rxSize);
int dmaWaitTransfers(u32 txSize, u32 rxSize);

#endif // DMA_H