VERSION 5.00
Begin VB.Form FormColorHalftone 
   BackColor       =   &H80000005&
   BorderStyle     =   4  'Fixed ToolWindow
   Caption         =   " Color halftone"
   ClientHeight    =   6510
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
   ScaleHeight     =   434
   ScaleMode       =   3  'Pixel
   ScaleWidth      =   806
   ShowInTaskbar   =   0   'False
   Visible         =   0   'False
   Begin PhotoDemon.pdCommandBar cmdBar 
      Align           =   2  'Align Bottom
      Height          =   750
      Left            =   0
      TabIndex        =   0
      Top             =   5760
      Width           =   12090
      _ExtentX        =   21325
      _ExtentY        =   1323
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
   Begin PhotoDemon.pdSlider sltAngle 
      Height          =   705
      Index           =   0
      Left            =   6000
      TabIndex        =   2
      Top             =   2520
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "cyan angle"
      Max             =   360
      SigDigits       =   1
   End
   Begin PhotoDemon.pdSlider sltRadius 
      Height          =   705
      Left            =   6000
      TabIndex        =   3
      Top             =   600
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "radius"
      Min             =   2
      Max             =   50
      SigDigits       =   1
      Value           =   5
      DefaultValue    =   5
   End
   Begin PhotoDemon.pdSlider sltAngle 
      Height          =   705
      Index           =   1
      Left            =   6000
      TabIndex        =   4
      Top             =   3480
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "magenta angle"
      Max             =   360
      SigDigits       =   1
      DefaultValue    =   33.3
   End
   Begin PhotoDemon.pdSlider sltAngle 
      Height          =   705
      Index           =   2
      Left            =   6000
      TabIndex        =   5
      Top             =   4440
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "yellow angle"
      Max             =   360
      SigDigits       =   1
      DefaultValue    =   66.7
   End
   Begin PhotoDemon.pdSlider sltDensity 
      Height          =   705
      Left            =   6000
      TabIndex        =   6
      Top             =   1560
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "density"
      Max             =   100
      SigDigits       =   1
      Value           =   100
      NotchPosition   =   2
      NotchValueCustom=   100
   End
End
Attribute VB_Name = "FormColorHalftone"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
'***************************************************************************
'Color Halftone Effect Interface
'Copyright 2014-2017 by Tanner Helland
'Created: 01/April/15
'Last updated: 01/April/15
'Last update: initial build
'
'Color halftoning creates a magazine-like effect, using circles of varying size, varying angle, and density to
' recreate an image using a traditional CMYK print function.
'
'Thank you to Plinio Garcia for suggesting this effect to me.
'
'This tool's algorithm is a modified version of a function originally written by Jerry Huxtable of JH Labs.
' Jerry's original code is licensed under an Apache 2.0 license (http://www.apache.org/licenses/LICENSE-2.0).
' You may download his original version from the following link (good as of March '15):
' http://www.jhlabs.com/ip/filters/index.html
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

'Apply a CMYK halftone filter to the current image.
Public Sub ColorHalftoneFilter(ByVal pxRadius As Double, ByVal cyanAngle As Double, ByVal magentaAngle As Double, ByVal yellowAngle As Double, ByVal dotDensity As Double, Optional ByVal toPreview As Boolean = False, Optional ByRef dstPic As pdFxPreviewCtl)
    
    If (Not toPreview) Then Message "Printing image to digital halftone surface..."
    
    'Create a local array and point it at the pixel data of the current image
    Dim dstSA As SAFEARRAY2D
    PrepImageData dstSA, toPreview, dstPic
    
    'Create a second local array.  This will contain the a copy of the current image, and we will use it as our source reference
    ' (This is necessary to prevent converted pixel values from spreading across the image as we go.)
    Dim srcDIB As pdDIB
    Set srcDIB = New pdDIB
    srcDIB.CreateFromExistingDIB workingDIB
    
    'Modify the radius value for previews
    If toPreview Then pxRadius = pxRadius * curDIBValues.previewModifier
    If pxRadius < 2 Then pxRadius = 2
    
    'Use the external function to apply the actual effect
    Filters_Stylize.CreateColorHalftoneDIB pxRadius, cyanAngle, magentaAngle, yellowAngle, dotDensity, srcDIB, workingDIB, toPreview
    
    srcDIB.EraseDIB
    Set srcDIB = Nothing
    
    'Pass control to finalizeImageData, which will handle the rest of the rendering
    FinalizeImageData toPreview, dstPic
        
    
End Sub

Private Sub cmdBar_OKClick()
    Process "Color halftone", , BuildParams(sltRadius.Value, sltAngle(0).Value, sltAngle(1).Value, sltAngle(2).Value, sltDensity.Value), UNDO_LAYER
End Sub

Private Sub cmdBar_RequestPreviewUpdate()
    UpdatePreview
End Sub

Private Sub Form_Load()

    'Suspend previews while we initialize controls
    cmdBar.MarkPreviewStatus False
        
    'Apply translations and themes
    ApplyThemeAndTranslations Me
    
    'Request a preview
    cmdBar.MarkPreviewStatus True
    UpdatePreview
    
End Sub

Private Sub Form_Unload(Cancel As Integer)
    ReleaseFormTheming Me
End Sub

'Redraw the effect preview
Private Sub UpdatePreview()
    If cmdBar.PreviewsAllowed Then ColorHalftoneFilter sltRadius.Value, sltAngle(0).Value, sltAngle(1).Value, sltAngle(2).Value, sltDensity.Value, True, pdFxPreview
End Sub

Private Sub pdFxPreview_ViewportChanged()
    UpdatePreview
End Sub

Private Sub sltAngle_Change(Index As Integer)
    UpdatePreview
End Sub

Private Sub sltDensity_Change()
    UpdatePreview
End Sub

Private Sub sltRadius_Change()
    UpdatePreview
End Sub

Private Function GetLocalParamString() As String
    
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    
    With cParams
    
    End With
    
    GetLocalParamString = cParams.GetParamString()
    
End Function
