#include "UnavailableCFunctions.h"

int swift_fcntl(int fildes, int cmd, int arg){
    return fcntl(fildes, cmd, arg);
}

int swift_close(int fd){
    return close(fd);
}
int swift_htons(int portNum){
    return htons(portNum);
}