#import "VCMCPRelay.h"
#import "VCMCPServer.h"
#import <sys/socket.h>
#import <sys/un.h>
#import <signal.h>

static int VCConnectToSocket(NSString *path) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    struct sockaddr_un address;
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    strlcpy(address.sun_path, path.fileSystemRepresentation, sizeof(address.sun_path));

    if (connect(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
        close(fd);
        return -1;
    }
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
    return fd;
}

int VCRunMCPRelay(void) {
    signal(SIGPIPE, SIG_IGN);
    NSString *path = [VCMCPServer socketPath];

    // Connect, launching the menu-bar app if it isn't running. `open` keeps
    // Screen Recording permission attributed to Visual Coach, not the client.
    int fd = VCConnectToSocket(path);
    if (fd < 0) {
        system("open -g -b local.codex.visualcoach.agent");
        for (int attempt = 0; attempt < 20 && fd < 0; attempt++) {
            usleep(500000);
            fd = VCConnectToSocket(path);
        }
    }
    if (fd < 0) {
        fprintf(stderr, "visual-coach: could not reach the Visual Coach app. Is it installed and running?\n");
        return 1;
    }

    // socket → stdout
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        char buffer[65536];
        ssize_t count;
        while ((count = read(fd, buffer, sizeof(buffer))) > 0) {
            fwrite(buffer, 1, (size_t)count, stdout);
            fflush(stdout);
        }
        exit(0);
    });

    // stdin → socket
    char buffer[65536];
    ssize_t count;
    while ((count = read(STDIN_FILENO, buffer, sizeof(buffer))) > 0) {
        ssize_t offset = 0;
        while (offset < count) {
            ssize_t written = write(fd, buffer + offset, (size_t)(count - offset));
            if (written <= 0) return 1;
            offset += written;
        }
    }
    close(fd);
    return 0;
}
