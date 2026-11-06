/*
 * FX local recursive DNS health probe. The endpoint is restricted to IPv4 loopback.
 * NXDOMAIN is a valid DNS answer; malformed, truncated, mismatched or non-recursive
 * replies are failures.
 */
#define _POSIX_C_SOURCE 200809L
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

static void put16(unsigned char *p, uint16_t v) { p[0]=(unsigned char)(v>>8); p[1]=(unsigned char)v; }
static int parse_long_arg(const char *s,long min,long max,long *out) {
    char *end=NULL; long v;
    if(!s || !*s) return -1;
    errno=0; v=strtol(s,&end,10);
    if(errno==ERANGE || end==s || *end!='\0' || v<min || v>max) return -1;
    *out=v; return 0;
}
static int add_label(unsigned char *out,size_t *n,const char *s) {
    size_t len=strlen(s);
    if(len==0 || len>63 || *n+len+1>=512) return -1;
    out[(*n)++]=(unsigned char)len; memcpy(out+*n,s,len); *n+=len; return 0;
}
static int remaining_ms(const struct timespec *deadline) {
    struct timespec now;
    int64_t ns;
    if(clock_gettime(CLOCK_MONOTONIC,&now)!=0) return -1;
    ns=(int64_t)(deadline->tv_sec-now.tv_sec)*1000000000LL+
       (int64_t)deadline->tv_nsec-now.tv_nsec;
    if(ns<=0) return 0;
    if(ns/1000000LL>2147483647LL) return 2147483647;
    return (int)((ns+999999LL)/1000000LL);
}
static int wait_socket(int fd,short events,const struct timespec *deadline) {
    struct pollfd pfd;
    int ms,rc;
    pfd.fd=fd; pfd.events=events;
    for(;;) {
        ms=remaining_ms(deadline);
        if(ms<=0) return -1;
        pfd.revents=0;
        rc=poll(&pfd,1,ms);
        if(rc<0 && errno==EINTR) continue;
        if(rc<=0 || (pfd.revents&(POLLERR|POLLHUP|POLLNVAL))!=0) return -1;
        if((pfd.revents&events)!=0) return 0;
    }
}
static int transfer_all(int fd,unsigned char *buf,size_t len,int sending,
                        const struct timespec *deadline) {
    size_t offset=0;
    while(offset<len) {
        ssize_t count=sending?send(fd,buf+offset,len-offset,MSG_NOSIGNAL):recv(fd,buf+offset,len-offset,0);
        if(count<0 && errno==EINTR) continue;
        if(count<0 && (errno==EAGAIN || errno==EWOULDBLOCK)) {
            if(wait_socket(fd,sending?POLLOUT:POLLIN,deadline)!=0) return -1;
            continue;
        }
        if(count<=0) return -1;
        offset+=(size_t)count;
    }
    return 0;
}
static int retry_tcp(const struct sockaddr_in *server,const unsigned char *query,size_t query_len,
                     unsigned char *reply,size_t reply_cap,const struct timeval *timeout,size_t *reply_len) {
    unsigned char prefix[2],frame[514];
    uint16_t length;
    int fd=socket(AF_INET,SOCK_STREAM,0),flags,connect_rc,so_error=0;
    socklen_t so_error_len=sizeof(so_error);
    struct timespec deadline;
    int wait_ms;
    if(fd<0) return -1;
    if(query_len>512 || timeout->tv_sec<0 || timeout->tv_sec>10) { close(fd); return -1; }
    if(clock_gettime(CLOCK_MONOTONIC,&deadline)!=0) { close(fd); return -1; }
    deadline.tv_sec+=timeout->tv_sec;
    deadline.tv_nsec+=timeout->tv_usec*1000L;
    if(deadline.tv_nsec>=1000000000L) { deadline.tv_sec++; deadline.tv_nsec-=1000000000L; }
    flags=fcntl(fd,F_GETFL,0);
    if(flags<0 || fcntl(fd,F_SETFL,flags|O_NONBLOCK)!=0) { close(fd); return -1; }
    connect_rc=connect(fd,(const struct sockaddr *)server,sizeof(*server));
    if(connect_rc!=0 && errno!=EINPROGRESS) { close(fd); return -1; }
    if(connect_rc!=0) {
        wait_ms=remaining_ms(&deadline);
        if(wait_ms<=0 || wait_socket(fd,POLLOUT,&deadline)!=0 ||
           getsockopt(fd,SOL_SOCKET,SO_ERROR,&so_error,&so_error_len)!=0 || so_error!=0) {
            close(fd); return -1;
        }
    }
    put16(prefix,(uint16_t)query_len);
    memcpy(frame,prefix,2); memcpy(frame+2,query,query_len);
    if(transfer_all(fd,frame,query_len+2,1,&deadline)!=0 || transfer_all(fd,prefix,2,0,&deadline)!=0) {
        close(fd); return -1;
    }
    length=(uint16_t)(((uint16_t)prefix[0]<<8)|prefix[1]);
    if(length<12 || (size_t)length>reply_cap || transfer_all(fd,reply,length,0,&deadline)!=0) {
        close(fd); return -1;
    }
    close(fd); *reply_len=(size_t)length; return 0;
}
int main(int argc,char **argv) {
    const char *ip=argc>1?argv[1]:"127.0.0.1";
    long port=5353,timeout=5;
    struct sockaddr_in server; struct timeval tv; struct timespec ts;
    unsigned char query[512]={0},reply[4096]; uint16_t id,flags,rcode,qdcount;
    size_t n=12; int fd; char label[64];
    if(argc>4 || (argc>2 && parse_long_arg(argv[2],1,65535,&port)!=0) ||
       (argc>3 && parse_long_arg(argv[3],1,10,&timeout)!=0)) {
        fputs("invalid DNS probe arguments (port 1..65535, timeout 1..10 seconds)\n",stderr); return 64;
    }
    memset(&server,0,sizeof(server)); server.sin_family=AF_INET; server.sin_port=htons((uint16_t)port);
    if(inet_pton(AF_INET,ip,&server.sin_addr)!=1 ||
       (ntohl(server.sin_addr.s_addr)&0xff000000u)!=0x7f000000u) {
        fputs("DNS probe endpoint must be an IPv4 loopback address (127.0.0.0/8)\n",stderr); return 64;
    }
    tv.tv_sec=timeout; tv.tv_usec=0;
    if(clock_gettime(CLOCK_MONOTONIC,&ts)!=0) { ts.tv_sec=time(NULL); ts.tv_nsec=(long)getpid()*7919L; }
    id=(uint16_t)(((uint64_t)ts.tv_nsec^(uint64_t)ts.tv_sec^(uint64_t)getpid())&0xffffu);
    put16(query,id); put16(query+2,0x0100u); put16(query+4,1u);
    (void)snprintf(label,sizeof(label),"fx-health-%08lx-%08lx",(unsigned long)ts.tv_sec,(unsigned long)ts.tv_nsec);
    if(add_label(query,&n,label)!=0 || add_label(query,&n,"example")!=0 || add_label(query,&n,"com")!=0) {
        fputs("failed to encode health query\n",stderr); return 65;
    }
    query[n++]=0; put16(query+n,1u); n+=2; put16(query+n,1u); n+=2;
    fd=socket(AF_INET,SOCK_DGRAM,0); if(fd<0) { perror("socket"); return 70; }
    if(setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&tv,sizeof(tv))!=0 ||
       setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&tv,sizeof(tv))!=0) {
        perror("DNS probe socket timeout"); close(fd); return 70;
    }
    if(connect(fd,(struct sockaddr *)&server,sizeof(server))!=0) { perror("connect"); close(fd); return 70; }
    if(send(fd,query,n,0)!=(ssize_t)n) { perror("send"); close(fd); return 71; }
    ssize_t udp_got=recv(fd,reply,sizeof(reply),0);
    if(udp_got<0) { perror("recv"); close(fd); return 72; } close(fd);
    if(udp_got<12) { fputs("DNS response shorter than header\\n",stderr); return 72; }
    flags=(uint16_t)(((uint16_t)reply[2]<<8)|reply[3]);
    size_t got=(size_t)udp_got;
    if((flags&0x0200u)!=0 && retry_tcp(&server,query,n,reply,sizeof(reply),&tv,&got)!=0) {
        fputs("truncated UDP DNS response and TCP retry failed\\n",stderr); return 72;
    }
    if(got<n) { fputs("DNS response shorter than echoed question\\n",stderr); return 72; }
    uint16_t response_id=(uint16_t)(((uint16_t)reply[0]<<8)|reply[1]);
    flags=(uint16_t)(((uint16_t)reply[2]<<8)|reply[3]); rcode=(uint16_t)(flags&0x000fu);
    qdcount=(uint16_t)(((uint16_t)reply[4]<<8)|reply[5]);
    if(response_id!=id || (flags&0x8000u)==0 || (flags&0x7800u)!=0 ||
       (flags&0x0100u)==0 || (flags&0x0200u)!=0 || (flags&0x0070u)!=0 || qdcount!=1 ||
       memcmp(reply+12,query+12,n-12)!=0) {
        fputs("invalid DNS response ID/QR/opcode/RD/TC/question fields\n",stderr); return 73;
    }
    if((flags&0x0080u)==0) { fputs("DNS response did not advertise recursive availability\n",stderr); return 74; }
    if(rcode!=0 && rcode!=3) { fprintf(stderr,"DNS resolver returned error RCODE=%u\n",(unsigned)rcode); return 75; }
    printf("PASS rcode=%u bytes=%ld port=%ld\n",(unsigned)rcode,(long)got,port); return 0;
}
