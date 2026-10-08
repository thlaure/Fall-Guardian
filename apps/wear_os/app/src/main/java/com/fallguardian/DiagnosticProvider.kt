package com.fallguardian

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.Binder
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.os.Process
import java.io.FileNotFoundException

/** Explicit ADB-only export in Release. DUMP permission plus UID check exclude
 * ordinary apps. No arbitrary filenames, settings, credentials or alert actions.
 */
class DiagnosticProvider : ContentProvider() {
    override fun onCreate(): Boolean {
        FallDiagnostics.initialize(requireNotNull(context))
        return true
    }

    private fun checkCaller() {
        val uid = Binder.getCallingUid()
        if (uid != 2000 && uid != Process.myUid()) throw SecurityException("ADB shell only")
    }

    override fun call(method: String, arg: String?, extras: Bundle?): Bundle {
        checkCaller()
        when (method) {
            "enable" -> FallDiagnostics.setEnabled(requireNotNull(context), true)
            "disable" -> FallDiagnostics.setEnabled(requireNotNull(context), false)
            "status" -> Unit
            else -> throw IllegalArgumentException("Unknown diagnostic method")
        }
        return Bundle().apply { putString("status", FallDiagnostics.status()) }
    }

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor {
        checkCaller()
        require(uri.path == "/status")
        return MatrixCursor(arrayOf("status")).apply { addRow(arrayOf(FallDiagnostics.status())) }
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        checkCaller()
        if (uri.path != "/export" || mode != "r") throw FileNotFoundException("Read-only diagnostic export")
        val pipe = ParcelFileDescriptor.createPipe()
        FallDiagnostics.export(ParcelFileDescriptor.AutoCloseOutputStream(pipe[1]))
        return pipe[0]
    }

    override fun getType(uri: Uri): String {
        checkCaller()
        return if (uri.path == "/export") "application/zip" else "text/plain"
    }
    override fun insert(uri: Uri, values: ContentValues?): Uri? = throw UnsupportedOperationException()
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = throw UnsupportedOperationException()
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = throw UnsupportedOperationException()
}
