/* Normalized work buffer: interleaved (x, log(y)-log(y0)), 16 bytes/sample. */
.equ WORK_DATA,0
.equ WORK_COUNT,8
.equ WORK_T0,16
.equ WORK_SPAN,24
.equ WORK_LOG_Y0,32
.equ WORK_SIZE,40
.equ FIT_K,0
.equ FIT_HALF,8
.equ FIT_LOG_A,16
.equ FIT_RMSE,24
.equ FIT_R2,32
.equ FIT_SIZE,40
/* Generic one-input/one-output CUDA launch descriptor. */
.equ JOB_IMAGE,0
.equ JOB_NAME,8
.equ JOB_ARGS,16
.equ JOB_INPUT,24
.equ JOB_INPUT_BYTES,32
.equ JOB_INPUT_SLOT,40
.equ JOB_OUTPUT,48
.equ JOB_OUTPUT_BYTES,56
.equ JOB_OUTPUT_SLOT,64
.equ JOB_GRID,72
.equ JOB_SIZE,80
.equ MAX_SAMPLES,1000000
