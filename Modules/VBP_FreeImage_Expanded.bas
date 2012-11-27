Attribute VB_Name = "FreeImage_Expanded_Interface"
'***************************************************************************
'FreeImage Interface (Advanced)
'Copyright �2011-2012 by Tanner Helland
'Created: 3/September/12
'Last updated: 25/November/12
'Last update: improved tone-mapping for high-bit-depth images with alpha channels
'
'This module represents a new - and significantly more complex - approach to loading images via the FreeImage libary.
' It handles a variety of decisions on a per-format basis to ensure optimal load speed and quality.
'
'Several sections of this module are based on the work of Herman Liu, to whom I am very grateful.
'
'Additionally, this module continues to rely heavily on Carsten Klein's FreeImage wrapper for VB (included in this project
' as Outside_FreeImageV3; see that file for license details).  Thanks to Carsten for his work on integrating FreeImage
' into classic VB.
'
'***************************************************************************

Option Explicit

'When loading a multipage image, the user will be prompted to load each page as an individual image.  If the user agrees,
' this variable will be set to TRUE.  PreLoadImage will then use this variable to launch the import of the subsequent pages.
Public imageHasMultiplePages As Boolean
Public imagePageCount As Long

'DIB declarations
Private Declare Function SetDIBitsToDevice Lib "gdi32" (ByVal hDC As Long, ByVal x As Long, ByVal y As Long, ByVal dx As Long, ByVal dy As Long, ByVal srcX As Long, ByVal srcY As Long, ByVal Scan As Long, ByVal NumScans As Long, Bits As Any, BitsInfo As Any, ByVal wUsage As Long) As Long
    
'Load an image via FreeImage.  It is assumed that the source file has already been vetted for things like "does it exist?"
Public Function LoadFreeImageV3_Advanced(ByVal SrcFilename As String, ByRef dstLayer As pdLayer, ByRef dstImage As pdImage, Optional ByVal pageToLoad As Long = 0) As Boolean

    On Error GoTo FreeImageV3_AdvancedError
    
    '****************************************************************************
    ' Make sure FreeImage exists and is usable
    '****************************************************************************
    
    'Double-check that FreeImage.dll was located at start-up
    If imageFormats.FreeImageEnabled = False Then
        LoadFreeImageV3_Advanced = False
        Exit Function
    End If
    
    'Load the FreeImage library from the plugin directory
    Dim hFreeImgLib As Long
    hFreeImgLib = LoadLibrary(PluginPath & "FreeImage.dll")
    
    '****************************************************************************
    ' Determine image format
    '****************************************************************************
    
    Message "Analyzing filetype..."
    
    'While we could manually test our extension against the FreeImage database, it is capable of doing so itself.
    'First, check the file header to see if it matches a known head type
    Dim fileFIF As FREE_IMAGE_FORMAT
    fileFIF = FreeImage_GetFileType(SrcFilename)
    
    'For certain filetypes (CUT, MNG, PCD, TARGA and WBMP, according to the FreeImage documentation), the lack of a reliable
    ' header may prevent GetFileType from working.  As a result, double-check the file using its file extension.
    If fileFIF = FIF_UNKNOWN Then fileFIF = FreeImage_GetFIFFromFilename(SrcFilename)
    
    'By this point, if the file still doesn't show up in FreeImage's database, abandon the import attempt.
    If Not FreeImage_FIFSupportsReading(fileFIF) Then
        Message "Filetype not supported by FreeImage.  Import abandoned."
        FreeLibrary hFreeImgLib
        LoadFreeImageV3_Advanced = False
        Exit Function
    End If
    
    'Store this file format inside the relevant pdImage object
    dstImage.OriginalFileFormat = fileFIF
    
    '****************************************************************************
    ' Based on the detected format, prepare any necessary load flags
    '****************************************************************************
    
    Message "Preparing import flags..."
    
    'Certain filetypes offer import options.  Check the FreeImage type to see if we want to enable any optional flags.
    Dim fi_ImportFlags As FREE_IMAGE_LOAD_OPTIONS
    fi_ImportFlags = 0
    
    'For JPEGs, specify a preference for accuracy and quality over load speed under normal circumstances,
    ' but when performing a batch conversion choose the reverse (speed over accuracy).
    If fileFIF = FIF_JPEG Then
        If MacroStatus = MacroBATCH Then
            fi_ImportFlags = FILO_JPEG_FAST
        Else
            fi_ImportFlags = FILO_JPEG_ACCURATE
        End If
    End If
    
    'For icons, we prefer a white background (default is black).
    ' NOTE: this is disabled, because it uses the AND mask incorrectly for mixed-format icons
    'If fileFIF = FIF_ICO Then fi_ImportFlags = FILO_ICO_MAKEALPHA
    
    '****************************************************************************
    ' Check GIF, TIFF, and ICO files for multiple pages (frames)
    '****************************************************************************
    
    Dim fi_multi_hDIB As Long
    Dim needToCloseMulti As Boolean

    If pageToLoad > 0 Then needToCloseMulti = True Else needToCloseMulti = False
    
    'If the image is a GIF, it might be animated.  Check for that now.
    If ((fileFIF = FIF_GIF) Or (fileFIF = FIF_TIFF)) And (pageToLoad = 0) And (MacroStatus <> MacroBATCH) Then
    
        If fileFIF = FIF_GIF Then
            fi_multi_hDIB = FreeImage_OpenMultiBitmap(FIF_GIF, SrcFilename)
        Else
            fi_multi_hDIB = FreeImage_OpenMultiBitmap(FIF_TIFF, SrcFilename)
        End If
        
        'Check the "page count" (e.g. frames) of the loaded GIF
        Dim chkPageCount As Long
        chkPageCount = FreeImage_GetPageCount(fi_multi_hDIB)
        
        FreeImage_CloseMultiBitmap fi_multi_hDIB
        
        'If the page count is more than 1, offer to load each page as an individual image
        If chkPageCount > 1 Then
            
            If fileFIF = FIF_GIF Then
                Message "Animated GIF file detected."
            Else
                Message "Multipage TIFF file detected."
            End If
            
            'Based on the user's preference for multipage images, we can handle the image one of several ways
            Select Case userPreferences.GetPreference_Long("General Preferences", "MultipageImagePrompt", 0)
            
                'Prompt the user for an action
                Case 0
                
                    Dim mpImportAnswer As VbMsgBoxResult
                    If fileFIF = FIF_GIF Then
                        mpImportAnswer = MsgBox("This is an animated GIF file (" & chkPageCount & " frames total).  Would you like to import each frame as its own image?" & vbCrLf & vbCrLf & "Select ""Yes"" to load each frame as an individual image, for a total of " & chkPageCount & " images." & vbCrLf & vbCrLf & "Select ""No"" to load only the first frame.", vbInformation + vbYesNo + vbApplicationModal, " Animated GIF Import Options")
                    Else
                        mpImportAnswer = MsgBox("This TIFF file contains multiple pages (" & chkPageCount & " pages total).  Would you like to import each page as its own image?" & vbCrLf & vbCrLf & "Select ""Yes"" to load each page as an individual image, for a total of " & chkPageCount & " images." & vbCrLf & vbCrLf & "Select ""No"" to load only the first page.", vbInformation + vbYesNo + vbApplicationModal, " Multipage TIFF Import Options")
                    End If
                    
                    'If the user said "yes", import each page as its own image
                    If mpImportAnswer = vbYes Then
                    
                        If fileFIF = FIF_GIF Then
                            Message "All frames will be loaded, per the user's request."
                        Else
                            Message "All pages will be loaded, per the user's request."
                        End If
                    
                        imageHasMultiplePages = True
                        imagePageCount = chkPageCount - 1
                                    
                    'If the user just wants the first frame, close the image and resume normal loading
                    
                    Else
                        
                        If fileFIF = FIF_GIF Then
                            Message "Only the first frame will be loaded, per the user's request."
                        Else
                            Message "Only the first page will be loaded, per the user's request."
                        End If
                        
                        imageHasMultiplePages = False
                        imagePageCount = 0
                    
                    End If
                
                'Ignore additional images, and treat this as a single-image file.  (Load just the first frame or page, basically.)
                Case 1
                
                    Message "Ignoring extra images in the file, per user's saved preference."
                    imageHasMultiplePages = False
                    imagePageCount = 0
                
                'Load every image in the file.
                Case 2
                
                    Message "Loading all images in the file, per user's saved preference."
                    imageHasMultiplePages = True
                    imagePageCount = chkPageCount - 1
                
            End Select
            
        End If
        
    End If
    
    '****************************************************************************
    ' Load the image into a FreeImage container
    '****************************************************************************
        
    'With all flags set and filetype correctly determined, import the image
    Dim fi_hDIB As Long
    
    If pageToLoad = 0 Then
        Message "Importing image from file..."
        fi_hDIB = FreeImage_Load(fileFIF, SrcFilename, fi_ImportFlags)
    Else
        If fileFIF = FIF_GIF Then
            Message "Importing frame #" & pageToLoad & " from animated GIF file..."
            fi_multi_hDIB = FreeImage_OpenMultiBitmap(FIF_GIF, SrcFilename, , , , FILO_GIF_PLAYBACK)
        Else
            Message "Importing page #" & pageToLoad & " from multipage TIFF file..."
            fi_multi_hDIB = FreeImage_OpenMultiBitmap(FIF_TIFF, SrcFilename, , , , 0)
        End If
        fi_hDIB = FreeImage_LockPage(fi_multi_hDIB, pageToLoad)
    End If
    
    'If an empty handle is returned, abandon the import attempt.
    If fi_hDIB = 0 Then
        Message "Import via FreeImage failed (blank handle)."
        FreeLibrary hFreeImgLib
        LoadFreeImageV3_Advanced = False
        Exit Function
    End If
    
    '****************************************************************************
    ' Determine native color depth
    '****************************************************************************
    
    'Before we continue the import, we need to make sure the pixel data is in a format appropriate for PhotoDemon.
    
    Message "Analyzing color depth..."
    
    'First thing we want to check is the color depth.  PhotoDemon is designed around 16 million color images.  This could
    ' change in the future, but for now, force high-bit-depth images to a more appropriate 24 or 32bpp.
    Dim fi_BPP As Long
    fi_BPP = FreeImage_GetBPP(fi_hDIB)
    
    'If a high bit-depth image is incoming, we need to use a temporary layer to hold the image's alpha data (which will
    ' be erased by the tone-mapping algorithm we'll use).  This is that object
    Dim tmpAlphaRequired As Boolean, tmpAlphaCopySuccess As Boolean
    tmpAlphaRequired = False
    tmpAlphaCopySuccess = False
    
    Dim tmpAlphaLayer As pdLayer
    
    'A number of other variables may be required as we adjust the bit-depth of the image to match PhotoDemon's internal requirements.
    Dim new_hDIB As Long
    
    Dim fi_hasTransparency As Boolean
    Dim fi_transparentEntries As Long
    
    '****************************************************************************
    ' If the image is > 32bpp, downsample it to 24 or 32bpp
    '****************************************************************************
    
    'First, check source images without an alpha channel.  Convert these using the superior tone mapping method.
    If (fi_BPP = 48) Or (fi_BPP = 96) Then
    
        Message "High bit-depth RGB image identified.  Checking for non-standard alpha encoding..."
        
        'While images with these bit-depths may not have an alpha channel, they can have binary transparency - check for that now.
        ' (Note: as of FreeImage 3.15.3 binary bit-depths are not detected correctly.  That said, they may someday be supported -
        ' so I've implemented two checks to cover both contingencies.
        fi_hasTransparency = FreeImage_IsTransparent(fi_hDIB)
        fi_transparentEntries = FreeImage_GetTransparencyCount(fi_hDIB)
    
        'As of 25 Nov 2012, the user can choose to disable tone-mapping (which makes HDR loading much faster, but reduces image quality).
        ' Check that preference before tone-mapping the image.
        If userPreferences.GetPreference_Boolean("General Preferences", "UseToneMapping", True) Then
                
            'If the image has transparency, make a copy of the alpha data for future use
            If fi_hasTransparency Or (fi_transparentEntries <> 0) Then
                
                Message "Non-standard alpha data found.  Making temporary copy prior to tone mapping..."
                
                new_hDIB = FreeImage_ConvertColorDepth(fi_hDIB, FICF_RGB_32BPP, False)
                
                Set tmpAlphaLayer = New pdLayer
                tmpAlphaCopySuccess = tmpAlphaLayer.createBlank(FreeImage_GetWidth(new_hDIB), FreeImage_GetHeight(new_hDIB), 32)
        
                'Make sure the blank DIB creation worked
                If tmpAlphaCopySuccess Then tmpAlphaRequired = True
                
                'Copy the bits from the FreeImage DIB to our DIB
                'NOTE: investigate using AlphaBlend to copy the bits, with SourceConstantAlpha set to 255 (per http://msdn.microsoft.com/en-us/library/dd183393%28v=vs.85%29.aspx)
                ' This may be a way to preserve the alpha channel... assuming that this SetDIBitsToDevice is actually the problem, which it may not be.
                SetDIBitsToDevice tmpAlphaLayer.getLayerDC, 0, 0, FreeImage_GetWidth(new_hDIB), FreeImage_GetHeight(new_hDIB), 0, 0, 0, FreeImage_GetHeight(new_hDIB), ByVal FreeImage_GetBits(new_hDIB), ByVal FreeImage_GetInfo(new_hDIB), 0&
         
                'With the alpha data safely in the care of our temporary object, unload the temporary 32bpp version of this image
                FreeImage_UnloadEx new_hDIB
            Else
            
                Message "No alpha data found.  Preparing tone-mapping..."
            
            End If
            
            Message "Tone mapping HDR image to preserve tonal range..."
            
            new_hDIB = FreeImage_ToneMapping(fi_hDIB, FITMO_REINHARD05)
            
            If pageToLoad = 0 Then
                FreeImage_UnloadEx fi_hDIB
            Else
                needToCloseMulti = False
                FreeImage_UnlockPage fi_multi_hDIB, fi_hDIB, False
                FreeImage_CloseMultiBitmap fi_multi_hDIB
            End If
            
            fi_hDIB = new_hDIB
            
            Message "Tone mapping complete."
        
        Else
                
            If fi_hasTransparency Or (fi_transparentEntries <> 0) Then
            
                Message "Alpha found, but further tone-mapping ignored at user's request."
                new_hDIB = FreeImage_ConvertColorDepth(fi_hDIB, FICF_RGB_32BPP, False)
                
                If pageToLoad = 0 Then
                    FreeImage_UnloadEx fi_hDIB
                Else
                    needToCloseMulti = False
                    FreeImage_UnlockPage fi_multi_hDIB, fi_hDIB, False
                    FreeImage_CloseMultiBitmap fi_multi_hDIB
                End If
                
                fi_hDIB = new_hDIB
            
            Else
            
                Message "No alpha found.  Further tone-mapping ignored at user's request."
                new_hDIB = FreeImage_ConvertColorDepth(fi_hDIB, FICF_RGB_24BPP, False)
                
                If pageToLoad = 0 Then
                    FreeImage_UnloadEx fi_hDIB
                Else
                    needToCloseMulti = False
                    FreeImage_UnlockPage fi_multi_hDIB, fi_hDIB, False
                    FreeImage_CloseMultiBitmap fi_multi_hDIB
                End If
            
                fi_hDIB = new_hDIB
            
            End If
        
        End If
        
    End If
    
    'Because tone mapping may not preserve alpha channels (the FreeImage documentation is unclear on this),
    ' we must do the same as above - manually make a copy of the image's alpha data, then reduce the image using tone mapping.
    ' Later in the process we will restore the alpha data to the image.
    If (fi_BPP = 64) Or (fi_BPP = 128) Then
    
        'Again, check for the user's preference on tone-mapping
        If userPreferences.GetPreference_Boolean("General Preferences", "UseToneMapping", True) Then
        
            Message "High bit-depth RGBA image identified.  Making copy of alpha data..."
        
            new_hDIB = FreeImage_ConvertColorDepth(fi_hDIB, FICF_RGB_32BPP, False)
                
            Set tmpAlphaLayer = New pdLayer
            tmpAlphaCopySuccess = tmpAlphaLayer.createBlank(FreeImage_GetWidth(new_hDIB), FreeImage_GetHeight(new_hDIB), 32)
                
            'Make sure the blank DIB creation worked
            If tmpAlphaCopySuccess Then tmpAlphaRequired = True
                
            'Copy the bits from the FreeImage DIB to our DIB
            'NOTE: investigate using AlphaBlend to copy the bits, with SourceConstantAlpha set to 255 (per http://msdn.microsoft.com/en-us/library/dd183393%28v=vs.85%29.aspx)
            ' This may be a way to preserve the alpha channel... assuming that this SetDIBitsToDevice is actually the problem, which it may not be.
            SetDIBitsToDevice tmpAlphaLayer.getLayerDC, 0, 0, FreeImage_GetWidth(new_hDIB), FreeImage_GetHeight(new_hDIB), 0, 0, 0, FreeImage_GetHeight(new_hDIB), ByVal FreeImage_GetBits(new_hDIB), ByVal FreeImage_GetInfo(new_hDIB), 0&
         
            'With the alpha data safely in the care of our temporary object, unload the temporary 32bpp version of this image
            FreeImage_UnloadEx new_hDIB
        
            Message "Alpha copy complete.  Tone mapping HDR image to preserve tonal range..."
        
            'Now, convert the RGB data using the superior tone-mapping method.
            new_hDIB = FreeImage_ToneMapping(fi_hDIB, FITMO_REINHARD05)
            
            If pageToLoad = 0 Then
                FreeImage_UnloadEx fi_hDIB
            Else
                needToCloseMulti = False
                FreeImage_UnlockPage fi_multi_hDIB, fi_hDIB, False
                FreeImage_CloseMultiBitmap fi_multi_hDIB
            End If
            
            fi_hDIB = new_hDIB
            
            Message "Tone mapping complete."
            
        Else
        
            Message "High bit-depth RGBA image identified.  Tone-mapping ignored at user's request."
            new_hDIB = FreeImage_ConvertColorDepth(fi_hDIB, FICF_RGB_32BPP, False)
            
            If pageToLoad = 0 Then
                FreeImage_UnloadEx fi_hDIB
            Else
                needToCloseMulti = False
                FreeImage_UnlockPage fi_multi_hDIB, fi_hDIB, False
                FreeImage_CloseMultiBitmap fi_multi_hDIB
            End If
            
            fi_hDIB = new_hDIB
        
        End If
        
    End If
    
    '****************************************************************************
    ' If the image is < 24bpp, upsample it to 24bpp or 32bpp
    '****************************************************************************
    
    'Similarly, check for low-bit-depth images
    If fi_BPP < 24 Then
        
        'Next, check to see if this is actually a high-bit-depth grayscale image masquerading as a low-bit-depth RGB image
        Dim fi_imageType As FREE_IMAGE_TYPE
        fi_imageType = FreeImage_GetImageType(fi_hDIB)
        
        'If it is such a grayscale image, it requires a unique conversion operation
        If fi_imageType = FIT_UINT16 Then
            
            Message "Tone-mapping high-bit-depth grayscale image to 24bpp..."
            
            'First, convert it to a high-bit depth RGB image
            fi_hDIB = FreeImage_ConvertToRGB16(fi_hDIB)
            
            'Now use tone-mapping to reduce it back to 24bpp or 32bpp (contingent on the presence of transparency)
            fi_hasTransparency = FreeImage_IsTransparent(fi_hDIB)
            fi_transparentEntries = FreeImage_GetTransparencyCount(fi_hDIB)
        
            If fi_hasTransparency Or (fi_transparentEntries <> 0) Then
                new_hDIB = FreeImage_ConvertColorDepth(fi_hDIB, FICF_RGB_32BPP, False)
                
                If pageToLoad = 0 Then
                    FreeImage_UnloadEx fi_hDIB
                Else
                    needToCloseMulti = False
                    FreeImage_UnlockPage fi_multi_hDIB, fi_hDIB, False
                    FreeImage_CloseMultiBitmap fi_multi_hDIB
                End If
            
                fi_hDIB = new_hDIB
            Else
                new_hDIB = FreeImage_ToneMapping(fi_hDIB, FITMO_REINHARD05)
                
                If pageToLoad = 0 Then
                    FreeImage_UnloadEx fi_hDIB
                Else
                    needToCloseMulti = False
                    FreeImage_UnlockPage fi_multi_hDIB, fi_hDIB, False
                    FreeImage_CloseMultiBitmap fi_multi_hDIB
                End If
            
                fi_hDIB = new_hDIB
            End If
            
        Else
        
            'Conversion to higher bit depths is contingent on the presence of an alpha channel
            fi_hasTransparency = FreeImage_IsTransparent(fi_hDIB)
        
            'Images with an alpha channel are converted to 32 bit.  Without, 24.
            If fi_hasTransparency = True Then
                new_hDIB = FreeImage_ConvertColorDepth(fi_hDIB, FICF_RGB_32BPP, False)
                
                If pageToLoad = 0 Then
                    FreeImage_UnloadEx fi_hDIB
                Else
                    needToCloseMulti = False
                    FreeImage_UnlockPage fi_multi_hDIB, fi_hDIB, False
                    FreeImage_CloseMultiBitmap fi_multi_hDIB
                End If
            
                fi_hDIB = new_hDIB
            Else
                new_hDIB = FreeImage_ConvertColorDepth(fi_hDIB, FICF_RGB_24BPP, False)
                
                If pageToLoad = 0 Then
                    FreeImage_UnloadEx fi_hDIB
                Else
                    needToCloseMulti = False
                    FreeImage_UnlockPage fi_multi_hDIB, fi_hDIB, False
                    FreeImage_CloseMultiBitmap fi_multi_hDIB
                End If
            
                fi_hDIB = new_hDIB
            End If
            
        End If
        
    End If
    
    'By this point, we have loaded the image, and it is guaranteed to be at 24 or 32 bit color depth.  Verify it one final time.
    fi_BPP = FreeImage_GetBPP(fi_hDIB)
    
    '****************************************************************************
    ' Create a blank pdLayer, which will receive a copy of the image in DIB format
    '****************************************************************************
    
    'We are now finally ready to load the image.
    
    Message "Requesting memory for image transfer..."
    
    'Get width and height from the file, and create a new layer to match
    Dim fi_Width As Long, fi_Height As Long
    fi_Width = FreeImage_GetWidth(fi_hDIB)
    fi_Height = FreeImage_GetHeight(fi_hDIB)
    
    Dim creationSuccess As Boolean
    creationSuccess = dstLayer.createBlank(fi_Width, fi_Height, fi_BPP)
    
    'Make sure the blank DIB creation worked
    If creationSuccess = False Then
        Message "Import via FreeImage failed (couldn't create DIB)."
        
        If (pageToLoad = 0) Or (needToCloseMulti = False) Then
            FreeImage_UnloadEx fi_hDIB
        Else
            FreeImage_UnlockPage fi_multi_hDIB, fi_hDIB, False
            FreeImage_CloseMultiBitmap fi_multi_hDIB
        End If
        
        FreeLibrary hFreeImgLib
        LoadFreeImageV3_Advanced = False
        Exit Function
    End If
    
    '****************************************************************************
    ' Copy the data from the FreeImage object to the pdLayer object
    '****************************************************************************
    
    Message "Memory secured.  Finalizing image load..."
        
    'Copy the bits from the FreeImage DIB to our DIB
    SetDIBitsToDevice dstLayer.getLayerDC, 0, 0, fi_Width, fi_Height, 0, 0, 0, fi_Height, ByVal FreeImage_GetBits(fi_hDIB), ByVal FreeImage_GetInfo(fi_hDIB), 0&
              
    'With the image bits now safely in our care, release the FreeImage DIB
    If (pageToLoad = 0) Or (needToCloseMulti = False) Then
        FreeImage_UnloadEx fi_hDIB
    Else
        FreeImage_UnlockPage fi_multi_hDIB, fi_hDIB, False
        FreeImage_CloseMultiBitmap fi_multi_hDIB
    End If
        
    'Release the FreeImage library
    FreeLibrary hFreeImgLib
    
    Message "Image load successful.  FreeImage released."
    
    '****************************************************************************
    ' If necessary, restore any lost alpha data
    '****************************************************************************
    
    'We are almost done.  The last thing we need to do is restore the alpha values if this was a high-bit-depth image
    ' whose alpha data was lost during the tone-mapping phase.
    If tmpAlphaRequired Then
    
        Message "Restoring alpha data..."
        
        dstLayer.copyAlphaFromExistingLayer tmpAlphaLayer
        tmpAlphaLayer.eraseLayer
        Set tmpAlphaLayer = Nothing
        
        Message "Alpha data restored successfully."
        
    End If
    
    '****************************************************************************
    ' Load complete
    '****************************************************************************
    
    'Mark this load as successful
    LoadFreeImageV3_Advanced = True
    
    Exit Function
    
    '****************************************************************************
    ' Error handling
    '****************************************************************************
    
FreeImageV3_AdvancedError:

    'Release the FreeImage DIB if available
    If fi_hDIB <> 0 Then FreeImage_UnloadEx fi_hDIB
    
    'Release the FreeImage library
    If hFreeImgLib <> 0 Then FreeLibrary hFreeImgLib
    
    'Display a relevant error message
    Message "Import via FreeImage failed (Err#" & Err.Number & ")"
    
    'Mark this load as unsuccessful
    LoadFreeImageV3_Advanced = False
    
End Function
