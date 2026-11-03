package de.privacyguard.adhook.imported.dia;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import android.provider.DocumentsContract;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

/**
 * Dia 23.11 file/ELF library page.
 * File operations are restricted to a directory explicitly granted through SAF.
 * APK/SO inspection is read-only and limited to user-installed debuggable apps.
 */
public final class FxDiaFileActivity extends Activity {
    private static final int PICK_TREE = 7511, PICK_IMPORT = 7512, PICK_EXPORT = 7513;
    private static final int MAX_PREVIEW = 512 * 1024;
    private Uri treeUri, exportSource;
    private String exportName = "export.bin";
    private final List<String> pathStack = new ArrayList<>();
    private LinearLayout files;
    private TextView fileStatus, location, soStatus, soResults;
    private static final int DIRECTORY_PAGE_SIZE = 100;
    private static final int MAX_DIRECTORY_ENTRIES = 5000;
    private final ThreadPoolExecutor ioWorker = new ThreadPoolExecutor(2, 2, 30L,
            TimeUnit.SECONDS, new ArrayBlockingQueue<>(8),
            r -> new Thread(r, "fx-dia-file-io"), new ThreadPoolExecutor.AbortPolicy());
    private final List<Entry> directoryEntries = new ArrayList<>();
    private int displayedEntries;
    private boolean directoryTruncated;
    private long directoryRequestId;
    private Button loadMoreButton;
    private volatile boolean destroyed;

    private void postUi(Runnable action) {
        runOnUiThread(() -> {
            if (!destroyed && !isFinishing() && !isDestroyed()) action.run();
        });
    }

    private void submitIo(String operation, Runnable task) {
        try {
            ioWorker.execute(task);
        } catch (RejectedExecutionException full) {
            postUi(() -> fileStatus.setText(operation + "队列已满，请稍后重试。"));
        }
    }

    private int dp(float n) { return (int)(n * getResources().getDisplayMetrics().density + 0.5f); }
    private TextView text(String s, int size, int color, boolean bold) {
        TextView t = new TextView(this); t.setText(s); t.setTextSize(size); t.setTextColor(color);
        if (bold) t.setTypeface(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD);
        t.setPadding(dp(4), dp(5), dp(4), dp(5)); return t;
    }
    private Button button(String label, Runnable click) {
        Button b = new Button(this); b.setAllCaps(false); b.setText(label); b.setOnClickListener(v -> click.run()); return b;
    }
    private void card(LinearLayout body, String title, String detail, View... children) {
        LinearLayout panel = new LinearLayout(this); panel.setOrientation(1);
        panel.setPadding(dp(13), dp(8), dp(13), dp(8)); panel.setBackgroundColor(0xfff0f3f7);
        panel.addView(text(title, 15, 0xff17212b, true)); panel.addView(text(detail, 12, 0xff617080, false));
        for (View child : children) panel.addView(child);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(dp(12), dp(4), dp(12), dp(4)); body.addView(panel, lp);
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout root = new LinearLayout(this); root.setOrientation(1); root.setBackgroundColor(0xfff7f8fa);
        LinearLayout header = new LinearLayout(this); header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(10), dp(6), dp(12), dp(6));
        header.addView(button("‹ 返回", this::finish));
        header.addView(text("Dia 23.11 · 文件与 so 库", 18, 0xff17212b, true), new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);
        ScrollView scroll = new ScrollView(this); scroll.setFillViewport(true);
        LinearLayout body = new LinearLayout(this); body.setOrientation(1); body.setPadding(0, dp(4), 0, dp(18));
        scroll.addView(body); root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1)); setContentView(root);

        fileStatus = text("尚未授权文件目录。", 12, 0xff526170, false);
        location = text("未选择目录", 12, 0xff334155, false);
        files = new LinearLayout(this); files.setOrientation(1);
        card(body, "用户授权目录",
                "只管理用户通过系统文件选择器明确授权的目录，不扫描其他应用私有目录。",
                location, fileStatus, button("选择目录", this::pickTree),
                button("返回上一级", this::goUp), button("刷新目录", this::loadDirectory),
                button("导入文件", this::pickImport), button("新建文件夹", this::createFolder));
        card(body, "目录内容", "点击文件夹进入；小型文本文件可预览，文件可导出或删除。", files);

        soStatus = text("尚未选择 debuggable 目标。", 12, 0xff526170, false);
        soResults = text("", 11, 0xff334155, false);
        card(body, "APK 与 SO 库浏览",
                "只读列出用户安装且带 DEBUGGABLE 标记的应用 APK 中 lib/<ABI>/*.so 和 nativeLibraryDir；不加载、执行或修改 SO。",
                soStatus, button("选择 debuggable 应用并查看 SO", this::chooseDebugTarget), soResults);
        restoreTree();
    }

    private SharedPreferences prefs() { return getSharedPreferences("fx_dia_file_browser", MODE_PRIVATE); }
    private Uri parentUri() {
        if (treeUri == null || pathStack.isEmpty()) return null;
        return DocumentsContract.buildDocumentUriUsingTree(treeUri, pathStack.get(pathStack.size() - 1));
    }
    private void pickTree() {
        Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);
        i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
        try { startActivityForResult(i, PICK_TREE); }
        catch (Throwable e) { fileStatus.setText("无法打开目录选择器：" + e.getClass().getSimpleName()); }
    }
    private void acceptTree(Uri uri) {
        try {
            getContentResolver().takePersistableUriPermission(uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
            treeUri = uri; pathStack.clear(); pathStack.add(DocumentsContract.getTreeDocumentId(uri));
            prefs().edit().putString("tree_uri", uri.toString()).apply(); loadDirectory();
        } catch (Throwable e) { fileStatus.setText("保存目录授权失败：" + e.getClass().getSimpleName()); }
    }
    private void restoreTree() {
        String saved = prefs().getString("tree_uri", "");
        if (saved.isEmpty()) return;
        try {
            treeUri = Uri.parse(saved);
            getContentResolver().takePersistableUriPermission(treeUri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
            pathStack.clear(); pathStack.add(DocumentsContract.getTreeDocumentId(treeUri)); loadDirectory();
        } catch (Throwable e) { treeUri = null; fileStatus.setText("目录授权已失效，请重新选择。"); }
    }

    private static final class Entry {
        final String id, name, mime; final long size;
        Entry(String id, String name, String mime, long size) {
            this.id=id; this.name=name==null?"(未命名)":name;
            this.mime=mime==null?"application/octet-stream":mime; this.size=size;
        }
        boolean directory() { return DocumentsContract.Document.MIME_TYPE_DIR.equals(mime); }
    }

    private void loadDirectory() {
        if (treeUri == null || pathStack.isEmpty()) { fileStatus.setText("请先选择一个目录。"); return; }
        files.removeAllViews(); fileStatus.setText("正在读取目录…");
        String id = pathStack.get(pathStack.size()-1);
        location.setText("目录 ID：" + id);
        Uri children = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, id);
        String[] projection = { DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_SIZE };
        List<Entry> entries = new ArrayList<>();
        try (Cursor c = getContentResolver().query(children, projection, null, null,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME + " COLLATE NOCASE ASC")) {
            if (c != null) {
                int ci=c.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID);
                int cn=c.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME);
                int cm=c.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE);
                int cs=c.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE);
                while (c.moveToNext()) entries.add(new Entry(c.getString(ci), c.getString(cn),
                        c.getString(cm), cs<0?-1:c.getLong(cs)));
            }
        } catch (Throwable e) {
            fileStatus.setText("读取目录失败：" + e.getClass().getSimpleName()); return;
        }
        for (Entry e:entries) addEntry(e);
        fileStatus.setText("已读取 " + entries.size() + " 个项目。");
    }

    private Uri docUri(Entry entry) {
        return DocumentsContract.buildDocumentUriUsingTree(treeUri, entry.id);
    }
    private void addEntry(Entry e) {
        LinearLayout row = new LinearLayout(this); row.setOrientation(1);
        row.setPadding(dp(9), dp(5), dp(9), dp(5)); row.setBackgroundColor(0xffffffff);
        row.addView(text((e.directory()?"📁 ":"📄 ")+e.name, 13, 0xff17212b, true));
        row.addView(text(e.directory()?"文件夹":e.mime+" · "+(e.size<0?"大小未知":bytes(e.size)),
                10, 0xff718091, false));
        if (e.directory()) row.addView(button("进入文件夹", () -> {
            pathStack.add(e.id); loadDirectory();
        }));
        else {
            LinearLayout actions = new LinearLayout(this); actions.setOrientation(0);
            actions.addView(button("预览", () -> preview(e)));
            actions.addView(button("导出", () -> beginExport(e)));
            actions.addView(button("删除", () -> confirmDelete(e)));
            row.addView(actions);
        }
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(dp(8), dp(2), dp(8), dp(2)); files.addView(row, lp);
    }

    private void goUp() {
        if (pathStack.size() <= 1) { fileStatus.setText("已经位于授权目录根部。"); return; }
        pathStack.remove(pathStack.size()-1); loadDirectory();
    }
    private boolean validName(String n) {
        return n!=null && !n.trim().isEmpty() && n.length()<=120 && !n.contains("/") && !n.contains("\\")
                && n.indexOf('\n')<0 && n.indexOf('\r')<0;
    }
    private void createFolder() {
        if (treeUri==null) { fileStatus.setText("请先选择目录。"); return; }
        EditText name=new EditText(this); name.setSingleLine(true); name.setHint("文件夹名称");
        new AlertDialog.Builder(this).setTitle("新建文件夹").setView(name).setNegativeButton("取消",null)
                .setPositiveButton("创建",(d,w)->{
                    String v=name.getText().toString().trim();
                    if(!validName(v)){fileStatus.setText("文件夹名称无效。");return;}
                    try { DocumentsContract.createDocument(getContentResolver(),parentUri(),
                            DocumentsContract.Document.MIME_TYPE_DIR,v); loadDirectory(); }
                    catch(Throwable e){fileStatus.setText("创建失败："+e.getClass().getSimpleName());}
                }).show();
    }
    private void pickImport() {
        if(treeUri==null){fileStatus.setText("请先选择目录。");return;}
        Intent i=new Intent(Intent.ACTION_OPEN_DOCUMENT); i.addCategory(Intent.CATEGORY_OPENABLE); i.setType("*/*");
        try{startActivityForResult(i,PICK_IMPORT);}catch(Throwable e){fileStatus.setText("无法打开导入选择器。");}
    }
    private String displayName(Uri uri) {
        try(Cursor c=getContentResolver().query(uri,new String[]{android.provider.OpenableColumns.DISPLAY_NAME},null,null,null)){
            if(c!=null&&c.moveToFirst()){int ix=c.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME);
                if(ix>=0&&c.getString(ix)!=null&&validName(c.getString(ix)))return c.getString(ix);}
        }catch(Throwable ignored){}
        return "import.bin";
    }
    private void importFile(Uri uri) {
        String name=displayName(uri), mime=getContentResolver().getType(uri);
        if(mime==null)mime="application/octet-stream"; final String contentType=mime;
        fileStatus.setText("正在导入 "+name+"…");
        new Thread(()->{
            try(InputStream in=getContentResolver().openInputStream(uri)){
                if(in==null)throw new IllegalStateException("无法读取来源文件。");
                Uri created=DocumentsContract.createDocument(getContentResolver(),parentUri(),contentType,name);
                if(created==null)throw new IllegalStateException("无法创建目标文件。");
                try(OutputStream out=getContentResolver().openOutputStream(created,"w")){
                    if(out==null)throw new IllegalStateException("无法写入目标文件。");
                    byte[] b=new byte[16384];int n;while((n=in.read(b))!=-1)out.write(b,0,n);out.flush();
                }
                runOnUiThread(()->{fileStatus.setText("已导入 "+name);loadDirectory();});
            }catch(Throwable e){runOnUiThread(()->fileStatus.setText("导入失败："+e.getClass().getSimpleName()));}
        },"FxDiaFileImport").start();
    }
    private void preview(Entry e) {
        if(e.size>MAX_PREVIEW){fileStatus.setText("文件超过 512 KiB，仅显示元数据。");return;}
        new Thread(()->{
            try(InputStream in=getContentResolver().openInputStream(docUri(e));ByteArrayOutputStream out=new ByteArrayOutputStream()){
                if(in==null)throw new IllegalStateException("无法读取文件。");
                byte[] b=new byte[8192];int n;while((n=in.read(b))!=-1){if(out.size()>MAX_PREVIEW-n)throw new IllegalArgumentException("预览超过 512 KiB。");out.write(b,0,n);}
                String content=new String(out.toByteArray(),StandardCharsets.UTF_8);
                if(content.indexOf('\uFFFD')>=0)content="该文件可能不是 UTF-8 文本；字节数："+out.size();
                final String shown=content;
                runOnUiThread(()->{EditText view=new EditText(this);view.setText(shown);view.setMinLines(8);view.setTextIsSelectable(true);
                    new AlertDialog.Builder(this).setTitle(e.name).setView(view).setPositiveButton("关闭",null)
                            .setNeutralButton("复制文本",(d,w)->{android.content.ClipboardManager cm=(android.content.ClipboardManager)getSystemService(CLIPBOARD_SERVICE);
                                if(cm!=null)cm.setPrimaryClip(android.content.ClipData.newPlainText(e.name,shown));}).show();});
            }catch(Throwable error){runOnUiThread(()->fileStatus.setText("预览失败："+error.getClass().getSimpleName()));}
        },"FxDiaFilePreview").start();
    }
    private void beginExport(Entry e) {
        exportSource=docUri(e);exportName=e.name;
        Intent i=new Intent(Intent.ACTION_CREATE_DOCUMENT);i.addCategory(Intent.CATEGORY_OPENABLE);i.setType(e.mime);
        i.putExtra(Intent.EXTRA_TITLE,exportName);
        try{startActivityForResult(i,PICK_EXPORT);}catch(Throwable error){fileStatus.setText("无法打开导出选择器。");}
    }
    private void exportFile(Uri dest) {
        if(exportSource==null)return; final Uri src=exportSource;final String name=exportName;
        fileStatus.setText("正在导出 "+name+"…");
        new Thread(()->{
            try(InputStream in=getContentResolver().openInputStream(src);OutputStream out=getContentResolver().openOutputStream(dest,"w")){
                if(in==null||out==null)throw new IllegalStateException("无法打开来源或目标。");
                byte[] b=new byte[16384];int n;while((n=in.read(b))!=-1)out.write(b,0,n);out.flush();
                runOnUiThread(()->fileStatus.setText("已导出 "+name));
            }catch(Throwable e){runOnUiThread(()->fileStatus.setText("导出失败："+e.getClass().getSimpleName()));}
            finally{exportSource=null;}
        },"FxDiaFileExport").start();
    }
    private void confirmDelete(Entry e) {
        new AlertDialog.Builder(this).setTitle("删除文件").setMessage("仅删除所选授权目录中的文件：\n"+e.name)
                .setNegativeButton("取消",null).setPositiveButton("删除",(d,w)->{
                    try{DocumentsContract.deleteDocument(getContentResolver(),docUri(e));loadDirectory();}
                    catch(Throwable error){fileStatus.setText("删除失败："+error.getClass().getSimpleName());}
                }).show();
    }

    private void chooseDebugTarget() {
        List<ApplicationInfo> apps=new ArrayList<>();PackageManager pm=getPackageManager();
        try{for(ApplicationInfo a:pm.getInstalledApplications(0)){
            if(a.packageName==null||a.packageName.equals(getPackageName()))continue;
            if((a.flags&ApplicationInfo.FLAG_DEBUGGABLE)==0||(a.flags&ApplicationInfo.FLAG_SYSTEM)!=0)continue;
            apps.add(a);
        }}catch(Throwable e){soStatus.setText("读取应用列表失败："+e.getClass().getSimpleName());return;}
        apps.sort(Comparator.comparing(a->String.valueOf(pm.getApplicationLabel(a)).toLowerCase(Locale.ROOT)));
        if(apps.isEmpty()){soStatus.setText("没有用户安装的 debuggable 应用。");return;}
        String[] labels=new String[apps.size()];
        for(int i=0;i<apps.size();i++)labels[i]=String.valueOf(pm.getApplicationLabel(apps.get(i)))+"\n"+apps.get(i).packageName;
        new AlertDialog.Builder(this).setTitle("选择 debuggable 应用").setItems(labels,(d,w)->inspectSo(apps.get(w)))
                .setNegativeButton("取消",null).show();
    }
    private void inspectSo(ApplicationInfo app) {
        StringBuilder out=new StringBuilder();
        out.append("应用：").append(app.packageName).append('\n')
                .append("APK：").append(app.sourceDir).append('\n')
                .append("Native Library Dir：").append(app.nativeLibraryDir).append("\n\n");
        int count=0;List<String> apks=new ArrayList<>();apks.add(app.sourceDir);
        if(app.splitSourceDirs!=null)java.util.Collections.addAll(apks,app.splitSourceDirs);
        for(String apk:apks)try(ZipFile zip=new ZipFile(apk)){
            java.util.Enumeration<? extends ZipEntry> entries=zip.entries();
            while(entries.hasMoreElements()){ZipEntry e=entries.nextElement();
                if(!e.isDirectory()&&e.getName().startsWith("lib/")&&e.getName().endsWith(".so")){
                    out.append(e.getName()).append(" · ").append(e.getSize()<0?"大小未知":bytes(e.getSize())).append('\n');count++;
                }
            }
        }catch(Throwable error){out.append("APK 库目录不可读取：").append(apk).append('\n');}
        out.append("\n已安装 Native 目录：\n");
        File dir=app.nativeLibraryDir==null?null:new File(app.nativeLibraryDir);
        File[] libs=dir==null?null:dir.listFiles((d,n)->n.endsWith(".so"));
        if(libs==null)out.append("当前进程无权列出目录；APK 中的 SO 条目仍如上显示。\n");
        else for(File f:libs){out.append(f.getName()).append(" · ").append(bytes(f.length())).append('\n');count++;}
        soResults.setText(out.toString());soStatus.setText("只读列出 "+count+" 个 SO 条目；不执行、不注入、不修改。");
    }
    private String bytes(long n){
        if(n<1024)return n+" B";double x=n;String[] units={"B","KiB","MiB","GiB"};int i=0;
        while(x>=1024&&i<units.length-1){x/=1024;i++;}return String.format(Locale.ROOT,"%.2f %s",x,units[i]);
    }
    @Override protected void onActivityResult(int requestCode,int resultCode,Intent data){
        super.onActivityResult(requestCode,resultCode,data);if(resultCode!=RESULT_OK||data==null||data.getData()==null)return;
        Uri uri=data.getData();
        if(requestCode==PICK_TREE){
            try{getContentResolver().takePersistableUriPermission(uri,Intent.FLAG_GRANT_READ_URI_PERMISSION|Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
                treeUri=uri;pathStack.clear();pathStack.add(DocumentsContract.getTreeDocumentId(uri));
                prefs().edit().putString("tree_uri",uri.toString()).apply();loadDirectory();
            }catch(Throwable e){fileStatus.setText("保存目录授权失败："+e.getClass().getSimpleName());}
        }else if(requestCode==PICK_IMPORT)importFile(uri);
        else if(requestCode==PICK_EXPORT)exportFile(uri);
    }
}
