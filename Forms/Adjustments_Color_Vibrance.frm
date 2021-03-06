VERSION 5.00
Begin VB.Form FormVibrance 
   BackColor       =   &H80000005&
   BorderStyle     =   4  'Fixed ToolWindow
   Caption         =   " Vibrance"
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
   Begin PhotoDemon.pdSlider sltVibrance 
      Height          =   705
      Left            =   6000
      TabIndex        =   2
      Top             =   2400
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "vibrance"
      Min             =   -100
      Max             =   200
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
End
Attribute VB_Name = "FormVibrance"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
'***************************************************************************
'Vibrance Adjustment Tool
'Copyright 2013-2017 by Audioglider
'Created: 26/June/13
'Last updated: 20/July/17
'Last update: migrate to XML params
'
'Many thanks to talented contributer Audioglider for creating this tool.
'
'Vibrance is similar to saturation, but slightly smarter, more subtle.  The algorithm attempts to provide a greater boost
' to colors that are less saturated, while performing a smaller adjustment to already saturated colors.
'
'Positive values indicate "more vibrance", while negative values indicate "less vibrance"
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

Public Sub Vibrance(ByVal effectParams As String, Optional ByVal toPreview As Boolean = False, Optional ByRef dstPic As pdFxPreviewCtl)
    
    If (Not toPreview) Then Message "Adjusting color vibrance..."
    
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    cParams.SetParamString effectParams
    
    Dim vibranceAdjustment As Double
    vibranceAdjustment = cParams.GetDouble("vibrance", 0#)
    
    'Reverse the vibrance input; this way, positive values make the image more vibrant.  Negative values make it less vibrant.
    vibranceAdjustment = -0.01 * vibranceAdjustment
    
    'Create a local array and point it at the pixel data we want to operate on
    Dim imageData() As Byte
    Dim tmpSA As SAFEARRAY2D
    
    PrepImageData tmpSA, toPreview, dstPic
    CopyMemory ByVal VarPtrArray(imageData()), VarPtr(tmpSA), 4
        
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
    If (Not toPreview) Then ProgressBars.SetProgBarMax finalY
    progBarCheck = FindBestProgBarValue()
    
    'Color and related variables
    Dim r As Long, g As Long, b As Long, maxVal As Long
    Dim amtVal As Double, avgVal As Double
    
    'Build a look-up table of grayscale values (faster than calculating it manually for each pixel)
    Dim grayLookUp(0 To 765) As Byte
    For x = 0 To 765
        grayLookUp(x) = x \ 3
    Next x
        
    'Loop through each pixel in the image, converting values as we go
    initX = initX * qvDepth
    finalX = finalX * qvDepth
    
    For y = initY To finalY
    For x = initX To finalX Step qvDepth
        
        'Get the source pixel color values
        b = imageData(x, y)
        r = imageData(x + 2, y)
        g = imageData(x + 1, y)
        
        'Calculate the gray value using the look-up table
        avgVal = grayLookUp(r + g + b)
        maxVal = Max3Int(r, g, b)
        
        'Get adjusted average
        amtVal = ((Abs(maxVal - avgVal) / 127) * vibranceAdjustment)
        
        If (r <> maxVal) Then r = r + (maxVal - r) * amtVal
        If (g <> maxVal) Then g = g + (maxVal - g) * amtVal
        If (b <> maxVal) Then b = b + (maxVal - b) * amtVal
        
        'Clamp values to [0,255] range
        If (r < 0) Then r = 0
        If (r > 255) Then r = 255
        If (g < 0) Then g = 0
        If (g > 255) Then g = 255
        If (b < 0) Then b = 0
        If (b > 255) Then b = 255
        
        imageData(x, y) = b
        imageData(x + 1, y) = g
        imageData(x + 2, y) = r
        
    Next x
        If (Not toPreview) Then
            If (y And progBarCheck) = 0 Then
                If Interface.UserPressedESC() Then Exit For
                SetProgBarVal y
            End If
        End If
    Next y
    
    'Safely deallocate imageData()
    CopyMemory ByVal VarPtrArray(imageData), 0&, 4
    
    'Pass control to finalizeImageData, which will handle the rest of the rendering
    FinalizeImageData toPreview, dstPic

End Sub

Private Sub cmdBar_OKClick()
    Process "Vibrance", , GetLocalParamString(), UNDO_LAYER
End Sub

Private Sub cmdBar_RequestPreviewUpdate()
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

'Update the preview whenever the combination slider/text control has its value changed
Private Sub sltVibrance_Change()
    UpdatePreview
End Sub

Private Sub UpdatePreview()
    If cmdBar.PreviewsAllowed Then Vibrance GetLocalParamString(), True, pdFxPreview
End Sub

'If the user changes the position and/or zoom of the preview viewport, the entire preview must be redrawn.
Private Sub pdFxPreview_ViewportChanged()
    UpdatePreview
End Sub

Private Function GetLocalParamString() As String
    
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    
    With cParams
        .AddParam "vibrance", sltVibrance.Value
    End With
    
    GetLocalParamString = cParams.GetParamString()
    
End Function
