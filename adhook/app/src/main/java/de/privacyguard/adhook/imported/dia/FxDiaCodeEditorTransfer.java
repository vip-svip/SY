package de.privacyguard.adhook.imported.dia;
import android.content.Context;
import android.util.AtomicFile;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.UUID;
/** Atomic app-private editor handoff; Binder transports only a short file path. */
final class FxDiaCodeEditorTransfer {
 private static final String PREFIX="fx-dia-code-editor-";
 private FxDiaCodeEditorTransfer(){}
 static String create(Context c,String source)throws Exception{
  String p=new File(c.getCacheDir(),PREFIX+UUID.randomUUID()+".source").getAbsolutePath();
  write(c,p,source);return p;
 }
 static String sibling(Context c,String path,String suffix)throws Exception{
  File f=checked(c,path);if(!f.getName().endsWith(".source"))throw new SecurityException("Invalid source");
  String n=f.getName();return new File(c.getCacheDir(),n.substring(0,n.length()-7)+suffix).getAbsolutePath();
 }
 static String read(Context c,String path,String suffix)throws Exception{
  File f=checked(c,path);if(!f.getName().endsWith(suffix))throw new SecurityException("Invalid suffix");
  try(InputStream in=new AtomicFile(f).openRead();ByteArrayOutputStream out=new ByteArrayOutputStream()){
   byte[] b=new byte[16384];int n;while((n=in.read(b))!=-1)out.write(b,0,n);
   return new String(out.toByteArray(),StandardCharsets.UTF_8);
  }
 }
 static void write(Context c,String path,String source)throws Exception{
  AtomicFile a=new AtomicFile(checked(c,path));FileOutputStream out=null;
  try{out=a.startWrite();out.write(source.getBytes(StandardCharsets.UTF_8));out.flush();a.finishWrite(out);}
  catch(Exception e){if(out!=null)a.failWrite(out);throw e;}
 }
 static void delete(Context c,String path){if(path==null)return;try{new AtomicFile(checked(c,path)).delete();}catch(Exception ignored){}}
 private static File checked(Context c,String path)throws Exception{
  if(path==null)throw new SecurityException("Missing path");
  File f=new File(path).getCanonicalFile(),d=c.getCacheDir().getCanonicalFile();String n=f.getName();
  if(!d.equals(f.getParentFile())||!n.startsWith(PREFIX)
   ||!(n.endsWith(".source")||n.endsWith(".result")||n.endsWith(".draft")))
   throw new SecurityException("Transfer path outside app cache");
  return f;
 }
}