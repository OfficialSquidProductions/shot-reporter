package org.squidproductions.camerastats.android

import android.app.Activity
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import org.squidproductions.camerastats.core.*
import org.squidproductions.camerastats.ui.*
import java.io.File
import java.io.ByteArrayOutputStream
import java.io.FileOutputStream

class MainActivity:ComponentActivity(),PlatformGateway {
    override val label="Android"
    override val brand:ImageBitmap by lazy {assets.open("brand.png").use {BitmapFactory.decodeStream(it).asImageBitmap()}}
    private var repository:Repository?=null
    lateinit var model:AppState;private set
    private var importComplete:((ByteArray?)->Unit)?=null
    private var exportComplete:(()->Unit)?=null
    private var pendingExport:String?=null
    private val openDocument=registerForActivityResult(ActivityResultContracts.OpenDocument()) {uri ->
        if(uri==null) {importComplete?.invoke(null);importComplete=null}
        else try {val data=readBounded(uri);val callback=importComplete;importComplete=null;if(callback!=null) callback(data) else model.pending=Exchange.read(data)} catch(e:Exception) {model.fail(e)}
    }
    private val createDocument=registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {result ->
        val cached=pendingExport?.let(::File)
        try {
            val uri=result.data?.data
            if(result.resultCode==Activity.RESULT_OK && uri!=null) {
                require(cached?.isFile==true) {"Pending export could not be recovered. Existing local report is preserved; export again."}
                contentResolver.openOutputStream(uri,"wt")?.use {output ->cached!!.inputStream().use {it.copyTo(output)};output.flush()} ?: throw ReportException("Selected destination could not be written.")
                exportComplete?.invoke()
            }
        } catch(e:Exception) {model.fail(e)} finally {cached?.delete();pendingExport=null;exportComplete=null}
    }
    override fun onCreate(savedInstanceState:Bundle?) {
        super.onCreate(savedInstanceState);pendingExport=savedInstanceState?.getString("pendingExport")
        val result=runCatching {Repository(AndroidDriver(File(filesDir,"reports.sqlite3")))};repository=result.getOrNull()
        model=AppState(repository,this);result.exceptionOrNull()?.let {model.error="Local reports could not be read. Existing bytes preserved. ${it.message}"}
        setContent {FieldApp(model)}
    }
    override fun onSaveInstanceState(outState:Bundle) {outState.putString("pendingExport",pendingExport);super.onSaveInstanceState(outState)}
    override fun onDestroy() {repository?.close();super.onDestroy()}
    override fun notices():String=assets.open("open-source-notices.txt").bufferedReader().use {it.readText()}
    override fun preference(key:String,fallback:String):String=getSharedPreferences("workspace",MODE_PRIVATE).getString(key,fallback) ?: fallback
    override fun preference(key:String,value:String,write:Boolean) {getSharedPreferences("workspace",MODE_PRIVATE).edit().putString(key,value).apply()}
    override fun importFile(complete:(ByteArray?)->Unit) {importComplete=complete;openDocument.launch(arrayOf("application/octet-stream","application/zip","*/*"))}
    override fun exportFile(name:String,mime:String,bytes:ByteArray,complete:()->Unit) {
        require(pendingExport==null) {"Finish or cancel the current export first."}
        val cached=File.createTempFile("camera-report-",".export",cacheDir)
        try {FileOutputStream(cached).use {it.write(bytes);it.fd.sync()};pendingExport=cached.absolutePath;exportComplete=complete
            createDocument.launch(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {addCategory(Intent.CATEGORY_OPENABLE);type=mime;putExtra(Intent.EXTRA_TITLE,name)})
        } catch(e:Exception) {cached.delete();pendingExport=null;exportComplete=null;throw e}
    }
    private fun readBounded(uri:Uri):ByteArray = contentResolver.openInputStream(uri)?.use {input ->
        val output=ByteArrayOutputStream();val buffer=ByteArray(8192);while(true) {val count=input.read(buffer);if(count<0) break;require(output.size()+count<=Exchange.LIMIT) {"Report exceeds the 32 MiB alpha limit."};output.write(buffer,0,count)};output.toByteArray()
    } ?: throw ReportException("Selected report could not be read.")
    override fun pdf(report:Report):ByteArray=AndroidPDF.render(report)
}
