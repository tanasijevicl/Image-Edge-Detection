#ifndef SD_H
#define SD_H

#include "xil_util.h"

int sdCardConfig();
int sdReadFile(char* path, u8* buff, u32 size);
int sdWriteFile(char* path, u8* buff, u32 size);
int sdCardUnmount();

#endif // SD_H