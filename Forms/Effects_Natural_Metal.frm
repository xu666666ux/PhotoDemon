VERSION 5.00
Begin VB.Form FormMetal 
   BackColor       =   &H80000005&
   BorderStyle     =   4  'Fixed ToolWindow
   Caption         =   " Metal"
   ClientHeight    =   6540
   ClientLeft      =   45
   ClientTop       =   285
   ClientWidth     =   12030
   BeginProperty Font 
      Name            =   "Tahoma"
      Size            =   8.25
      Charset         =   0
      Weight          =   400
      Underline       =   0   'False
      Italic          =   0   'False
      Strikethrough   =   0   'False
   EndProperty
   LinkTopic       =   "Form1"
   MaxButton       =   0   'False
   MinButton       =   0   'False
   ScaleHeight     =   436
   ScaleMode       =   3  'Pixel
   ScaleWidth      =   802
   ShowInTaskbar   =   0   'False
   Begin PhotoDemon.pdCommandBar cmdBar 
      Align           =   2  'Align Bottom
      Height          =   750
      Left            =   0
      TabIndex        =   0
      Top             =   5790
      Width           =   12030
      _ExtentX        =   21220
      _ExtentY        =   1323
   End
   Begin PhotoDemon.pdSlider sltRadius 
      Height          =   705
      Left            =   6000
      TabIndex        =   2
      Top             =   1680
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "smoothness"
      Max             =   200
      SigDigits       =   1
      Value           =   20
      DefaultValue    =   20
   End
   Begin PhotoDemon.pdFxPreviewCtl pdFxPreview 
      Height          =   5625
      Left            =   120
      TabIndex        =   1
      Top             =   120
      Width           =   5625
      _ExtentX        =   9922
      _ExtentY        =   9922
   End
   Begin PhotoDemon.pdSlider sltDetail 
      Height          =   705
      Left            =   6000
      TabIndex        =   3
      Top             =   600
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "detail"
      Max             =   16
      Value           =   4
      NotchPosition   =   2
      NotchValueCustom=   4
   End
   Begin PhotoDemon.pdColorSelector csHighlight 
      Height          =   975
      Left            =   6000
      TabIndex        =   4
      Top             =   2760
      Width           =   5775
      _ExtentX        =   10186
      _ExtentY        =   1720
      Caption         =   "highlight color"
      curColor        =   14737632
   End
   Begin PhotoDemon.pdColorSelector csShadow 
      Height          =   975
      Left            =   6000
      TabIndex        =   5
      Top             =   3960
      Width           =   5775
      _ExtentX        =   10186
      _ExtentY        =   1720
      Caption         =   "shadow color"
      curColor        =   4210752
   End
End
Attribute VB_Name = "FormMetal"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
'***************************************************************************
'"Metal" or "Chrome" Image effect
'Copyright 2002-2017 by Tanner Helland
'Created: sometime 2002
'Last updated: 04/April/15
'Last update: rewrite function from scratch
'
'PhotoDemon's "Metal" filter is the rough equivalent of "Chrome" in Photoshop.  Our implementation is relatively
' straightforward; a normalized graymap is created for the image, then remapped according to a sinusoidal-like
' lookup table (created using the pdFilterLUT class).
'
'The user currently has control over two parameters: "smoothness", which determines a pre-effect blur radius,
' and "detail" which controls the number of octaves in the lookup table.
'
'Still TODO: allow the user to set a highlight and shadow color, instead of using boring ol' gray
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

'Apply a metallic "shimmer" to an image
Public Sub ApplyMetalFilter(ByVal steelDetail As Long, ByVal steelSmoothness As Double, Optional ByVal shadowColor As Long = 0, Optional ByVal highlightColor As Long = vbWhite, Optional ByVal toPreview As Boolean = False, Optional ByRef dstPic As pdFxPreviewCtl)
    
    If (Not toPreview) Then Message "Pouring smoldering metal onto image..."
    
    'Create a local array and point it at the pixel data of the current image
    Dim dstSA As SAFEARRAY2D
    PrepImageData dstSA, toPreview, dstPic
    
    'If this is a preview, we need to adjust the smoothness (kernel radius) to match the size of the preview box
    If toPreview Then steelSmoothness = steelSmoothness * curDIBValues.previewModifier
    
    'Decompose the shadow and highlight colors into their individual color components
    Dim rShadow As Long, gShadow As Long, bShadow As Long
    Dim rHighlight As Long, gHighlight As Long, bHighlight As Long
    
    rShadow = Colors.ExtractRed(shadowColor)
    gShadow = Colors.ExtractGreen(shadowColor)
    bShadow = Colors.ExtractBlue(shadowColor)
    
    rHighlight = Colors.ExtractRed(highlightColor)
    gHighlight = Colors.ExtractGreen(highlightColor)
    bHighlight = Colors.ExtractBlue(highlightColor)
    
    'Retrieve a normalized luminance map of the current image
    Dim grayMap() As Byte
    DIBs.GetDIBGrayscaleMap workingDIB, grayMap, True
    
    'If the user specified a non-zero smoothness, apply it now
    If steelSmoothness > 0 Then Filters_ByteArray.GaussianBlur_IIR_ByteArray grayMap, workingDIB.GetDIBWidth, workingDIB.GetDIBHeight, steelSmoothness, 3
        
    'Re-normalize the data (this ends up not being necessary, but it could be exposed to the user in a future update)
    'Filters_ByteArray.normalizeByteArray grayMap, workingDIB.getDIBWidth, workingDIB.getDIBHeight
    
    'Next, we need to generate a sinusoidal octave lookup table for the graymap.  This causes the luminance of the map to
    ' vary evently between the number of detail points requested by the user.
    
    'Detail cannot be lower than 2, but it is presented to the user as [0, (arbitrary upper bound)], so add two to the total now
    steelDetail = steelDetail + 2
    
    'We will be using pdFilterLUT to generate corresponding RGB lookup tables, which means we need to use POINTFLOAT arrays
    Dim rCurve() As POINTFLOAT, gCurve() As POINTFLOAT, bCurve() As POINTFLOAT
    ReDim rCurve(0 To steelDetail) As POINTFLOAT
    ReDim gCurve(0 To steelDetail) As POINTFLOAT
    ReDim bCurve(0 To steelDetail) As POINTFLOAT
    
    'For all channels, X values are evenly distributed from 0 to 255
    Dim i As Long
    For i = 0 To steelDetail
        rCurve(i).x = CDbl(i / steelDetail) * 255
        gCurve(i).x = CDbl(i / steelDetail) * 255
        bCurve(i).x = CDbl(i / steelDetail) * 255
    Next i
    
    'Y values alternate between the shadow and highlight colors; these are calculated on a per-channel basis
    For i = 0 To steelDetail
        
        If i Mod 2 = 0 Then
            rCurve(i).y = rShadow
            gCurve(i).y = gShadow
            bCurve(i).y = bShadow
        Else
            rCurve(i).y = rHighlight
            gCurve(i).y = gHighlight
            bCurve(i).y = bHighlight
        End If
        
    Next i
    
    'Convert our point array into color curves
    Dim rLookup() As Byte, gLookup() As Byte, bLookup() As Byte
    
    Dim cLut As pdFilterLUT
    Set cLut = New pdFilterLUT
    cLut.FillLUT_Curve rLookup, rCurve
    cLut.FillLUT_Curve gLookup, gCurve
    cLut.FillLUT_Curve bLookup, bCurve
        
    'We are now ready to apply the final curve to the image!
    
    'Create a local array and point it at the pixel data we want to operate on
    Dim imageData() As Byte
    CopyMemory ByVal VarPtrArray(imageData()), VarPtr(dstSA), 4
    
    'Local loop variables can be more efficiently cached by VB's compiler, so we transfer all relevant loop data here
    Dim x As Long, y As Long, initX As Long, initY As Long, finalX As Long, finalY As Long
    initX = curDIBValues.Left
    initY = curDIBValues.Top
    finalX = curDIBValues.Right
    finalY = curDIBValues.Bottom
            
    'These values will help us access locations in the array more quickly.
    ' (qvDepth is required because the image array may be 24 or 32 bits per pixel, and we want to handle both cases.)
    Dim quickVal As Long, qvDepth As Long
    qvDepth = curDIBValues.BytesPerPixel
    
    'To keep processing quick, only update the progress bar when absolutely necessary.  This function calculates that value
    ' based on the size of the area to be processed.
    Dim progBarCheck As Long
    progBarCheck = FindBestProgBarValue()
    
    Dim grayVal As Long
    
    'Apply the filter
    For x = initX To finalX
        quickVal = x * qvDepth
    For y = initY To finalY
        
        grayVal = grayMap(x, y)
        
        imageData(quickVal, y) = bLookup(grayVal)
        imageData(quickVal + 1, y) = gLookup(grayVal)
        imageData(quickVal + 2, y) = rLookup(grayVal)
        
    Next y
        If (x And progBarCheck) = 0 Then
            If Interface.UserPressedESC() Then Exit For
            SetProgBarVal x
        End If
    Next x
        
    'Safely deallocate imageData()
    CopyMemory ByVal VarPtrArray(imageData), 0&, 4
    
    'Pass control to finalizeImageData, which will handle the rest of the rendering using the data inside workingDIB
    FinalizeImageData toPreview, dstPic
            
End Sub

'OK button
Private Sub cmdBar_OKClick()
    Process "Metal", , BuildParams(sltDetail, sltRadius, csShadow.Color, csHighlight.Color), UNDO_LAYER
End Sub

Private Sub cmdBar_RequestPreviewUpdate()
    UpdatePreview
End Sub

Private Sub cmdBar_ResetClick()
    sltRadius.Value = 20
    sltDetail.Value = 4
    csShadow.Color = RGB(30, 30, 30)
    csHighlight.Color = RGB(230, 230, 230)
End Sub

Private Sub csHighlight_ColorChanged()
    UpdatePreview
End Sub

Private Sub csShadow_ColorChanged()
    UpdatePreview
End Sub

Private Sub Form_Load()
    cmdBar.MarkPreviewStatus False
    ApplyThemeAndTranslations Me
    cmdBar.MarkPreviewStatus True
    UpdatePreview
End Sub

Private Sub Form_Unload(Cancel As Integer)
    ReleaseFormTheming Me
End Sub

Private Sub UpdatePreview()
    If cmdBar.PreviewsAllowed Then ApplyMetalFilter sltDetail.Value, sltRadius.Value, csShadow.Color, csHighlight.Color, True, pdFxPreview
End Sub

Private Sub sltDetail_Change()
    UpdatePreview
End Sub

Private Sub sltRadius_Change()
    UpdatePreview
End Sub

'If the user changes the position and/or zoom of the preview viewport, the entire preview must be redrawn.
Private Sub pdFxPreview_ViewportChanged()
    UpdatePreview
End Sub

Private Function GetLocalParamString() As String
    
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    
    With cParams
    
    End With
    
    GetLocalParamString = cParams.GetParamString()
    
End Function
