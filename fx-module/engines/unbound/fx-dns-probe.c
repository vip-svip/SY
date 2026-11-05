/*
 * FX local recursive DNS health probe.
 * Sends a unique uncached A query to a caller-specified loopback endpoint.
 * NXDOMAIN is accepted as a valid DNS answer; SERVFAIL, timeout, mismatched IDs
 * and responses without recursion-available are treated as failures.
 */
#define _POSIX_C_SOURCE 200809L
#include <arpa/inet.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

static void put16(unsigned char *p, uint16_t v) {
    p[0] = (unsigned char)(v >> 8);
    p[1] = (unsigned char)(v & 0xff);
}

static int add_label(unsigned char *out, size_t *n, const char *s) {
    size_t len = strlen(s);
    if (len == 0 || len > 63 || *n + len + 1 >= 512) return -1;
    out[(*n)++] = (unsigned char)len;
    memcpy(out + *n, s, len);
    *n += len;
    return 0;
}

int main(int argc, char **argv) {
    const char *ip = argc > 1 ? argv[1] : "127.0.0.1";
    long port = argc > 2 ? strtol(argv[2], NULL, 10) : 5353;
    long timeout = argc > 3 ? strtol(argv[3], NULL, 10) : 5;
    struct sockaddr_in server;
    unsigned char query[512] = {0}, reply[4096];
    struct timeval tv = {5, 0};
    struct timespec ts;
    uint16_t id, flags, rcode;
    size_t n = 12;
    int fd;
    char label[64];

    if (port < 1 || port > 65535 || timeout < 1 || timeout > 10) {
        fputs("invalid DNS probe port/timeout (timeout must be 1..10 seconds)\n", stderr);
        return 64;
    }
    tv.tv_sec = timeout;
    memset(&server, 0, sizeof(server));
    server.sin_family = AF_INET;
    server.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, ip, &server.sin_addr) != 1) {
        fputs("invalid IPv4 loopback address\n", stderr);
        return 64;
    }
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
        ts.tv_sec = time(NULL);
        ts.tv_nsec = (long)getpid() * 7919L;
    }
    id = (uint16_t)(((uint64_t)ts.tv_nsec ^ (uint64_t)ts.tv_sec ^ (uint64_t)getpid()) & 0xffffu);
    put16(query, id);
    put16(query + 2, 0x0100u); /* RD */
    put16(query + 4, 1u);      /* QDCOUNT */
    (void)snprintf(label, sizeof(label), "fx-health-%08lx-%08lx",
                   (unsigned long)ts.tv_sec, (unsigned long)ts.tv_nsec);
    if (add_label(query, &n, label) != 0 ||
        add_label(query, &n, "example") != 0 ||
        add_label(query, &n, "com") != 0) {
        fputs("failed to encode health query\n", stderr);
        return 65;
    }
    query[n++] = 0;
    put16(query + n, 1u); n += 2; /* QTYPE A */
    put16(query + n, 1u); n += 2; /* QCLASS IN */

    fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) {
        perror("socket");
        return 70;
    }
    if (setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv)) != 0) {
        perror("SO_RCVTIMEO");
        close(fd);
        return 70;
    }
    if (connect(fd, (struct sockaddr *)&server, sizeof(server)) != 0) {
        perror("connect");
        close(fd);
        return 70;
    }
    if (send(fd, query, n, 0) != (ssize_t)n) {
        perror("send");
        close(fd);
        return 71;
    }
    ssize_t got = recv(fd, reply, sizeof(reply), 0);
    if (got < 12) {
        if (got < 0) perror("recv");
        else fputs("DNS response shorter than header\n", stderr);
        close(fd);
        return 72;
    }
    close(fd);

    uint16_t response_id = (uint16_t)(((uint16_t)reply[0] << 8) | reply[1]);
    flags = (uint16_t)(((uint16_t)reply[2] << 8) | reply[3]);
    rcode = (uint16_t)(flags & 0x000fu);
    if (response_id != id || (flags & 0x8000u) == 0 || (flags & 0x0100u) == 0) {
        fputs("invalid DNS response ID/QR/RD flags\n", stderr);
        return 73;
    }
    if ((flags & 0x0080u) == 0) {
        fputs("DNS response did not advertise recursive availability\n", stderr);
        return 74;
    }
    if (rcode != 0 && rcode != 3) {
        fprintf(stderr, "DNS resolver returned error RCODE=%u\n", (unsigned)rcode);
        return 75;
    }
    printf("PASS rcode=%u bytes=%ld port=%ld\n", (unsigned)rcode, (long)got, port);
    return 0;
}
