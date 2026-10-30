package de.privacyguard.adhook;
import java.nio.ByteBuffer;
/** Zeroes only the successfully-read portion of supported AudioRecord buffers. */
public final class AudioRecordSilencePolicy {
 private AudioRecordSilencePolicy() {}
 public static boolean supports(Class<?> type) { return type==byte[].class || type==short[].class || type==float[].class || ByteBuffer.class.isAssignableFrom(type); }
 public static void zero(Object[] args,int readCount,int byteBufferStart) {
  if(args==null||args.length==0||readCount<=0)return; Object buffer=args[0];
  int offset=args.length>1&&args[1] instanceof Integer?Math.max(0,(Integer)args[1]):0;
  if(buffer instanceof byte[]){byte[] a=(byte[])buffer;int n=Math.min(readCount,a.length-Math.min(offset,a.length));if(n>0)java.util.Arrays.fill(a,offset,offset+n,(byte)0);}
  else if(buffer instanceof short[]){short[] a=(short[])buffer;int n=Math.min(readCount,a.length-Math.min(offset,a.length));if(n>0)java.util.Arrays.fill(a,offset,offset+n,(short)0);}
  else if(buffer instanceof float[]){float[] a=(float[])buffer;int n=Math.min(readCount,a.length-Math.min(offset,a.length));if(n>0)java.util.Arrays.fill(a,offset,offset+n,0f);}
  else if(buffer instanceof ByteBuffer){ByteBuffer b=(ByteBuffer)buffer;int start=Math.max(0,byteBufferStart),end=Math.min(b.limit(),start+readCount);for(int i=start;i<end;i++)b.put(i,(byte)0);}
 }
}