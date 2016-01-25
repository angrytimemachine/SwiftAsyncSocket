#include <fcntl.h>
int swift_fcntl(int fildes, int cmd, int arg);

#include <unistd.h>
int swift_close(int fd);

#include <sys/socket.h>
#include <netinet/in.h>
int swift_htons(int portNum);