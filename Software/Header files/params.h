#ifndef PARAMS_H
#define PARAMS_H

#include "xil_util.h"

#define MAX_IMG_DIMENSION  512
#define MAX_FILENAME_LEN   255
#define MAX_PATH_LEN       260

// Processing parameters

typedef enum Mode {EDGE = 0, GRAD_H = 1, GRAD_V = 2, GRAD_M = 3} Mode_t;
typedef enum Border {ZERO = 0, CLOSEST_ELEM = 1} Border_t;
typedef enum Bypass {NO = 0, YES = 1} Bypass_t;

typedef struct Params {
	u16 ImgW;
    u16 ImgH;
    u16 EdgeThr;
    Mode_t Mode;
    Border_t Border;
    Bypass_t Bypass;
    char ImgName[MAX_FILENAME_LEN+1];
} Params_t;

#endif // PARAMS_H