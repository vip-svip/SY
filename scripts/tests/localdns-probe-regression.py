#!/usr/bin/env python3
"""Host integration tests for the FX loopback-only DNS health probe."""
import os, socket, struct, subprocess, tempfile, threading
SOURCE=os.path.join(os.path.dirname(__file__),"..","localdns-probe.c")
def run_case(binary,flags=0x8180,expect=0):
    srv=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); srv.bind(("127.0.0.1",0)); port=srv.getsockname()[1]
    def serve():
        try:
            packet,peer=srv.recvfrom(2048); packet=bytearray(packet); packet[2:4]=struct.pack("!H",flags); packet[6:12]=b"\0"*6
            srv.sendto(packet,peer)
        finally: srv.close()
    thread=threading.Thread(target=serve,daemon=True); thread.start()
    result=subprocess.run([binary,"127.0.0.1",str(port),"2"],capture_output=True,text=True,timeout=4)
    thread.join(timeout=3); assert result.returncode==expect,(result.returncode,result.stdout,result.stderr,expect)
    return result
def main():
    with tempfile.TemporaryDirectory(prefix="fx-dns-probe-") as tmp:
        binary=os.path.join(tmp,"probe")
        subprocess.run(["cc","-std=c11","-O2","-Wall","-Wextra","-Werror",SOURCE,"-o",binary],check=True)
        assert "PASS" in run_case(binary).stdout
        assert "PASS" in run_case(binary,0x8183).stdout
        assert run_case(binary,0x8080,73).returncode==73
        assert run_case(binary,0x8380,73).returncode==73
        remote=subprocess.run([binary,"192.0.2.1","5353","1"],capture_output=True,text=True,timeout=2)
        assert remote.returncode==64 and "loopback" in remote.stderr
        for args in (["127.0.0.1","5353junk"],["127.0.0.1","65536"],["127.0.0.1","5353","0"],["127.0.0.1","5353","1","extra"]):
            p=subprocess.run([binary]+args,capture_output=True,text=True,timeout=2); assert p.returncode==64,(args,p.returncode,p.stderr)
    print("PASS: loopback restriction, strict CLI parsing, valid/NXDOMAIN and malformed DNS response checks")
if __name__=="__main__": main()
