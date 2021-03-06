VERSION 5.00
Begin VB.Form FormGlassTiles 
   BackColor       =   &H80000005&
   BorderStyle     =   4  'Fixed ToolWindow
   Caption         =   " Glass tiles"
   ClientHeight    =   6540
   ClientLeft      =   45
   ClientTop       =   285
   ClientWidth     =   12090
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
   ScaleWidth      =   806
   ShowInTaskbar   =   0   'False
   Begin PhotoDemon.pdCommandBar cmdBar 
      Align           =   2  'Align Bottom
      Height          =   750
      Left            =   0
      TabIndex        =   0
      Top             =   5790
      Width           =   12090
      _ExtentX        =   21325
      _ExtentY        =   1323
   End
   Begin PhotoDemon.pdSlider sltAngle 
      Height          =   705
      Left            =   6000
      TabIndex        =   2
      Top             =   360
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "angle"
      Min             =   -45
      Max             =   45
      SigDigits       =   1
      Value           =   45
      DefaultValue    =   45
   End
   Begin PhotoDemon.pdFxPreviewCtl pdFxPreview 
      Height          =   5625
      Left            =   120
      TabIndex        =   1
      Top             =   120
      Width           =   5625
      _ExtentX        =   9922
      _ExtentY        =   9922
      DisableZoomPan  =   -1  'True
   End
   Begin PhotoDemon.pdSlider sltSize 
      Height          =   705
      Left            =   6000
      TabIndex        =   3
      Top             =   1440
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "size"
      Min             =   2
      Max             =   200
      Value           =   40
      DefaultValue    =   40
   End
   Begin PhotoDemon.pdSlider sltCurvature 
      Height          =   705
      Left            =   6000
      TabIndex        =   4
      Top             =   2520
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "curvature"
      Min             =   -20
      Max             =   20
      SigDigits       =   1
      Value           =   8
      DefaultValue    =   8
   End
   Begin PhotoDemon.pdSlider sltQuality 
      Height          =   705
      Left            =   6000
      TabIndex        =   6
      Top             =   3600
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "quality"
      Min             =   1
      Max             =   5
      Value           =   2
      NotchPosition   =   2
      NotchValueCustom=   2
   End
   Begin PhotoDemon.pdDropDown cboEdges 
      Height          =   735
      Left            =   6000
      TabIndex        =   5
      Top             =   4680
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1296
      Caption         =   "if pixels lie outside the image..."
   End
End
Attribute VB_Name = "FormGlassTiles"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
'***************************************************************************
'Glass Tiles Filter Dialog
'Copyright 2014 by Audioglider
'Created: 23/May/14
'Last updated: 26/July/17
'Last update: performance improvements, migrate to XML params
'
'"Glass tiles" is an image distortion filter that divides an image into clear glass blocks.  The curvature
' parameter generates a convex surface for positive values and a concave surface for negative values, while
' size and angle control exactly what you'd expect.
'
'Unlike other PD filters, this one supports supersampling for much better results along the curved edges of
' the glass blocks (where many source pixels become condensed into a single pixel in the destination image).
' Because of this unique feature, this filter supports a sliding quality scale instead of the usual binary
' choice of fast vs quality.  Regardless of the input quality, interpolation is always used for the source
' pixels; without it the results are simply subpar.
'
'Many thanks to pro developer Audioglider for contributing this great tool to PhotoDemon.
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

'Apply a glass tile filter to an image
Public Sub GlassTiles(ByVal effectParams As String, Optional ByVal toPreview As Boolean = False, Optional ByRef dstPic As pdFxPreviewCtl)
    
    If (Not toPreview) Then Message "Generating glass tiles..."
    
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    cParams.SetParamString effectParams
    
    Dim lSquareSize As Long, lCurvature As Double, lAngle As Double, superSamplingAmount As Long, edgeHandling As Long
    
    With cParams
        lSquareSize = .GetLong("size", sltSize.Value)
        lCurvature = .GetDouble("curvature", sltCurvature.Value)
        lAngle = .GetDouble("angle", sltAngle.Value)
        superSamplingAmount = .GetLong("quality", sltQuality.Value)
        edgeHandling = .GetLong("edges", cboEdges.ListIndex)
    End With
    
    'Create a local array and point it at the pixel data of the current image
    Dim dstImageData() As Byte
    Dim dstSA As SAFEARRAY2D
    PrepImageData dstSA, toPreview, dstPic
    CopyMemory ByVal VarPtrArray(dstImageData()), VarPtr(dstSA), 4
    
    'Create a second local array.  This will contain the a copy of the current image, and we will use it as our source reference
    ' (This is necessary to prevent diffused pixels from spreading across the image as we go.)
    Dim srcImageData() As Byte
    Dim srcSA As SAFEARRAY2D
    
    Dim srcDIB As pdDIB
    Set srcDIB = New pdDIB
    srcDIB.CreateFromExistingDIB workingDIB
    
    PrepSafeArray srcSA, srcDIB
    CopyMemory ByVal VarPtrArray(srcImageData()), VarPtr(srcSA), 4
        
    'During previews, we have to modify square size so that it reflects how the final image will look
    If toPreview Then
        lSquareSize = lSquareSize * curDIBValues.previewModifier
        If lSquareSize < 1 Then lSquareSize = 1
    End If
    
    'Convert angles to radians
    Dim m_Sin As Double, m_Cos As Double
    m_Sin = Sin(lAngle * (PI / 180))
    m_Cos = Cos(lAngle * (PI / 180))
    
    'Calculate scale and curvature values
    Dim m_Scale As Double, m_Curvature As Double
    m_Scale = PI / lSquareSize
    
    If lCurvature = 0# Then lCurvature = 0.1
    m_Curvature = lCurvature * lCurvature / 10# * (Abs(lCurvature) / lCurvature)
    
    'Due to the way this filter works, supersampling yields much better results (as the edges of the glass will take
    ' the values of many pixels, and condense them down to a single pixel).  Because supersampling is extremely
    ' energy-intensive, this is one of the few tools that uses a sliding value for quality, as opposed to a binary
    ' TRUE/FALSE for antialiasing.  (For all but the lowest quality setting, this tool will use antialiasing by default.)
    
    'Use the passed super-sampling constant (reported to the user as "quality") to come up with a number of actual
    ' pixels to sample.  (The total amount of sampled pixels will range from 1 to 18)
    Dim AA_Samples As Long
    AA_Samples = (superSamplingAmount * 2 - 1) * 2
    If (AA_Samples = 0) Then AA_Samples = 1
    
    Dim invAASamples As Double
    invAASamples = 1# / AA_Samples
    
    Dim m_aaPTX() As Single, m_aaPTY() As Single
    ReDim m_aaPTX(0 To AA_Samples - 1) As Single, m_aaPTY(0 To AA_Samples - 1) As Single
    Dim j As Double, k As Double
    
    'Precalculate all supersampling coordinate offsets
    Dim i As Long
    For i = 0 To AA_Samples - 1
        
        j = (i * 4) / CDbl(AA_Samples)
        k = i / CDbl(AA_Samples)
        
        j = j - CLng(j)
        
        m_aaPTX(i) = m_Cos * j + m_Sin * k
        m_aaPTY(i) = m_Cos * k - m_Sin * j
        
    Next i
            
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
    
    'Create a filter support class, which will aid with edge handling and interpolation
    Dim fSupport As pdFilterSupport
    Set fSupport = New pdFilterSupport
    fSupport.SetDistortParameters qvDepth, edgeHandling, True, curDIBValues.maxX, curDIBValues.maxY
    
    'To keep processing quick, only update the progress bar when absolutely necessary.  This function calculates that value
    ' based on the size of the area to be processed.
    Dim progBarCheck As Long
    progBarCheck = FindBestProgBarValue()
    
    'Color variables
    Dim r As Long, g As Long, b As Long, a As Long
    Dim newR As Long, newG As Long, newB As Long, newA As Long
    
    'Filter algorithm variables
    Dim hW As Double, hH As Double
    Dim mm As Long
    Dim xSample As Double, ySample As Double
    Dim u As Double, v As Double, s As Double, t As Double
    
    'Calculate half width/height in advance
    hW = finalX / 2
    hH = finalY / 2
        
    'Loop through each pixel in the image, converting values as we go
    For x = initX To finalX
        quickVal = x * qvDepth
    For y = initY To finalY
        
        'For rotation to work correctly, x/y offsets must be calculated relative to the center of the image
        j = x - hW
        k = y - hH
        
        newR = 0
        newG = 0
        newB = 0
        newA = 0
        
        'Sample a number of source pixels corresponding to the user's supplied quality value; more quality means
        ' more samples, and much better representation in the final output.
        For mm = 0 To AA_Samples - 1
        
            'Offset the pixel amount by the supersampling lookup table
            u = j + m_aaPTX(mm)
            v = k - m_aaPTY(mm)
            
            'Use magical math to calculate a glass tile effect
            s = (m_Cos * u) + (m_Sin * v)
            t = (-m_Sin * u) + (m_Cos * v)
            
            s = s + m_Curvature * Tan(s * m_Scale)
            t = t + m_Curvature * Tan(t * m_Scale)
            
            u = (m_Cos * s) - (m_Sin * t)
            v = (m_Sin * s) + (m_Cos * t)
            
            'Map the calculated sample locations relative to the top-left corner of the image
            xSample = hW + u
            ySample = hH + v
            
            'Use the filter support class to interpolate and edge-wrap pixels as necessary
            fSupport.GetColorsFromSource r, g, b, a, xSample, ySample, srcImageData
            
            'Add the retrieved values to our running averages
            newR = newR + r
            newG = newG + g
            newB = newB + b
            newA = newA + a
            
        Next mm
        
        'Find the average values of all samples, apply to the pixel, and move on!
        newR = newR * invAASamples
        newG = newG * invAASamples
        newB = newB * invAASamples
        newA = newA * invAASamples
        
        dstImageData(quickVal, y) = newB
        dstImageData(quickVal + 1, y) = newG
        dstImageData(quickVal + 2, y) = newR
        dstImageData(quickVal + 3, y) = newA
        
    Next y
        If (Not toPreview) Then
            If (x And progBarCheck) = 0 Then
                If Interface.UserPressedESC() Then Exit For
                SetProgBarVal x
            End If
        End If
    Next x
    
    'Safely deallocate all image arrays
    CopyMemory ByVal VarPtrArray(srcImageData), 0&, 4
    CopyMemory ByVal VarPtrArray(dstImageData), 0&, 4
    
    'Pass control to finalizeImageData, which will handle the rest of the rendering
    FinalizeImageData toPreview, dstPic
    
End Sub

Private Sub cboEdges_Click()
    UpdatePreview
End Sub

Private Sub cmdBar_OKClick()
    Process "Glass tiles", , GetLocalParamString(), UNDO_LAYER
End Sub

Private Sub cmdBar_RequestPreviewUpdate()
    UpdatePreview
End Sub

Private Sub cmdBar_ResetClick()
    sltAngle.Value = 45
    sltSize.Value = 40
    sltCurvature.Value = 8
    sltQuality.Value = 2
    cboEdges.ListIndex = EDGE_CLAMP
End Sub

Private Sub Form_Load()

    'Disable previewing until the form has been fully initialized
    cmdBar.MarkPreviewStatus False
    
    'I use a central function to populate the edge handling combo box; this way, I can add new methods and have
    ' them immediately available to all distort functions.
    PopDistortEdgeBox cboEdges, EDGE_CLAMP
    
    'Apply translations and visual themes
    ApplyThemeAndTranslations Me
    cmdBar.MarkPreviewStatus True
    UpdatePreview
    
End Sub

Private Sub Form_Unload(Cancel As Integer)
    ReleaseFormTheming Me
End Sub

Private Sub sltAngle_Change()
    UpdatePreview
End Sub

Private Sub sltCurvature_Change()
    UpdatePreview
End Sub

Private Sub sltQuality_Change()
    UpdatePreview
End Sub

Private Sub sltSize_Change()
    UpdatePreview
End Sub

Private Sub UpdatePreview()
    If cmdBar.PreviewsAllowed Then Me.GlassTiles GetLocalParamString(), True, pdFxPreview
End Sub

'If the user changes the position and/or zoom of the preview viewport, the entire preview must be redrawn.
Private Sub pdFxPreview_ViewportChanged()
    UpdatePreview
End Sub

Private Function GetLocalParamString() As String
    
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    
    With cParams
        .AddParam "size", sltSize.Value
        .AddParam "curvature", sltCurvature.Value
        .AddParam "angle", sltAngle.Value
        .AddParam "quality", sltQuality.Value
        .AddParam "edges", cboEdges.ListIndex
    End With
    
    GetLocalParamString = cParams.GetParamString()
    
End Function
