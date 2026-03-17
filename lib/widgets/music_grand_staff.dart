// lib/widgets/music_grand_staff.dart
// Grand Staff widget for piano notation with aligned measure widths

import 'package:flutter/material.dart';
import '../core/core.dart';
import '../src/layout/layout_engine.dart';
import '../src/rendering/staff_renderer.dart';
import '../src/rendering/staff_coordinate_system.dart';
import '../src/smufl/smufl_metadata_loader.dart';
import '../src/theme/music_score_theme.dart';

/// Widget for rendering grand staff (piano) notation with proper alignment.
/// 
/// Unlike stacking two [MusicScore] widgets, this ensures:
/// - Measure widths are synchronized between treble and bass staves
/// - A brace connects the staves visually
/// - Minimal vertical spacing between staves
/// 
/// Supports two layout modes:
/// - [wrapped] = false (default): Single horizontal line, scrolls horizontally
/// - [wrapped] = true: Multi-system layout that wraps to new lines, scrolls vertically
/// 
/// For single staff mode, pass only [trebleStaff] and leave [bassStaff] as null.
class MusicGrandStaff extends StatefulWidget {
  /// The treble (upper) staff - typically right hand
  final Staff trebleStaff;
  
  /// The bass (lower) staff - typically left hand
  /// If null, renders as a single staff (treble only)
  final Staff? bassStaff;
  
  /// Theme for rendering (colors, etc.)
  final MusicScoreTheme theme;
  
  /// Space between staff lines (in logical pixels)
  /// Default is 10.0 for compact grand staff
  final double staffSpace;
  
  /// Vertical gap between the two staves (in staff spaces)
  /// Default is 0 (staves rely on internal margins for separation)
  final double staffGap;
  
  /// Whether to draw a brace connecting the staves
  final bool showBrace;
  
  /// Whether to wrap to multiple systems (lines) like printed sheet music.
  /// - false (default): Single horizontal line with horizontal scrolling
  /// - true: Multi-system layout with vertical scrolling
  final bool wrapped;
  
  /// Number of measures per system when wrapped is true.
  /// If null, automatically calculated based on available width.
  final int? measuresPerSystem;

  const MusicGrandStaff({
    super.key,
    required this.trebleStaff,
    this.bassStaff,
    this.theme = const MusicScoreTheme(),
    this.staffSpace = 10.0,
    this.staffGap = 0,
    this.showBrace = true,
    this.wrapped = false,
    this.measuresPerSystem,
  });

  @override
  State<MusicGrandStaff> createState() => _MusicGrandStaffState();
}

class _MusicGrandStaffState extends State<MusicGrandStaff> {
  late Future<void> _metadataFuture;
  late SmuflMetadata _metadata;

  @override
  void initState() {
    super.initState();
    _metadata = SmuflMetadata();
    _metadataFuture = _metadata.load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _metadataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text('Error loading metadata: ${snapshot.error}'),
          );
        }

        // Delegate to appropriate layout mode
        if (widget.wrapped) {
          return _buildWrappedLayout();
        } else {
          return _buildHorizontalLayout();
        }
      },
    );
  }
  
  /// Build the wrapped (multi-system) layout with vertical scrolling
  Widget _buildWrappedLayout() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Determine if we're in single staff mode
        final isSingleStaff = widget.bassStaff == null;
        
        // Calculate how many measures fit per system
        final trebleLayoutCalc = LayoutEngine(
          widget.trebleStaff,
          availableWidth: constraints.maxWidth,
          staffSpace: widget.staffSpace,
          metadata: _metadata,
        );
        
        final bassLayoutCalc = isSingleStaff ? null : LayoutEngine(
          widget.bassStaff!,
          availableWidth: constraints.maxWidth,
          staffSpace: widget.staffSpace,
          metadata: _metadata,
        );

        final trebleMeasureLayouts = trebleLayoutCalc.calculateMeasureLayouts();
        final bassMeasureLayouts = bassLayoutCalc?.calculateMeasureLayouts() ?? [];
        
        final measureCount = trebleMeasureLayouts.length > bassMeasureLayouts.length 
            ? trebleMeasureLayouts.length 
            : bassMeasureLayouts.length;
        
        if (measureCount == 0) {
          return const Center(child: Text('Empty score'));
        }
        
        // Calculate synced measure widths
        final allMeasureWidths = <double>[];
        for (int i = 0; i < measureCount; i++) {
          final trebleWidth = i < trebleMeasureLayouts.length 
              ? trebleMeasureLayouts[i].minWidth 
              : 0.0;
          final bassWidth = i < bassMeasureLayouts.length 
              ? bassMeasureLayouts[i].minWidth 
              : 0.0;
          allMeasureWidths.add(trebleWidth > bassWidth ? trebleWidth : bassWidth);
        }
        
        // Calculate system margin space
        final marginSpace = widget.staffSpace * LayoutEngine.systemMargin * 2;
        final usableWidth = constraints.maxWidth - marginSpace;
        
        // Group measures into systems based on available width
        final systemMeasures = <List<int>>[];
        var currentSystem = <int>[];
        var currentSystemWidth = 0.0;
        
        // For first measure of each system, add space for clef + key sig + time sig
        // Estimate ~80 pixels for system elements
        final systemElementsWidth = widget.staffSpace * 8;
        
        for (int i = 0; i < measureCount; i++) {
          final measureWidth = allMeasureWidths[i];
          final isFirstInSystem = currentSystem.isEmpty;
          final widthNeeded = measureWidth + (isFirstInSystem ? systemElementsWidth : 0);
          
          // Check if this measure fits
          if (currentSystem.isNotEmpty && currentSystemWidth + widthNeeded > usableWidth) {
            // Start new system
            systemMeasures.add(currentSystem);
            currentSystem = [i];
            currentSystemWidth = measureWidth + systemElementsWidth;
          } else {
            currentSystem.add(i);
            currentSystemWidth += widthNeeded;
          }
        }
        
        // Add final system
        if (currentSystem.isNotEmpty) {
          systemMeasures.add(currentSystem);
        }
        
        // Override with explicit measures per system if specified
        if (widget.measuresPerSystem != null && widget.measuresPerSystem! > 0) {
          systemMeasures.clear();
          for (int i = 0; i < measureCount; i += widget.measuresPerSystem!) {
            final end = (i + widget.measuresPerSystem!) > measureCount 
                ? measureCount 
                : i + widget.measuresPerSystem!;
            systemMeasures.add(List.generate(end - i, (j) => i + j));
          }
        }
        
        // Calculate dimensions
        final singleStaffHeight = widget.staffSpace * 10;
        final gapHeight = widget.staffSpace * widget.staffGap;
        // For single staff mode, don't double the height
        final systemHeight = isSingleStaff 
            ? singleStaffHeight 
            : (singleStaffHeight + gapHeight + singleStaffHeight);
        final systemSpacing = widget.staffSpace * 3; // Gap between systems
        
        final numSystems = systemMeasures.length;
        final totalHeight = (numSystems * systemHeight) + 
            ((numSystems - 1) * systemSpacing) + 
            (widget.staffSpace * 2); // Top/bottom padding
        
        return SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: RepaintBoundary(
            child: CustomPaint(
              size: Size(constraints.maxWidth, totalHeight),
              painter: _WrappedGrandStaffPainter(
                trebleStaff: widget.trebleStaff,
                bassStaff: widget.bassStaff,
                metadata: _metadata,
                theme: widget.theme,
                staffSpace: widget.staffSpace,
                staffGap: widget.staffGap,
                showBrace: widget.showBrace && !isSingleStaff, // No brace for single staff
                singleStaffHeight: singleStaffHeight,
                grandStaffHeight: systemHeight,
                systemSpacing: systemSpacing,
                systemMeasures: systemMeasures,
                allMeasureWidths: allMeasureWidths,
                availableWidth: constraints.maxWidth,
              ),
            ),
          ),
        );
      },
    );
  }
  
  /// Build the horizontal (single-line) layout with horizontal scrolling
  Widget _buildHorizontalLayout() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
            // Determine if we're in single staff mode
            final isSingleStaff = widget.bassStaff == null;
            
            // === TWO-PASS LAYOUT FOR SYNCHRONIZED MEASURES ===
            
            // PASS 1: Calculate measure widths for both staves
            final trebleLayoutCalc = LayoutEngine(
              widget.trebleStaff,
              availableWidth: constraints.maxWidth,
              staffSpace: widget.staffSpace,
              metadata: _metadata,
            );
            
            final bassLayoutCalc = isSingleStaff ? null : LayoutEngine(
              widget.bassStaff!,
              availableWidth: constraints.maxWidth,
              staffSpace: widget.staffSpace,
              metadata: _metadata,
            );

            final trebleMeasureLayouts = trebleLayoutCalc.calculateMeasureLayouts();
            final bassMeasureLayouts = bassLayoutCalc?.calculateMeasureLayouts() ?? [];
            
            // Calculate max width for each measure (synchronized widths)
            final measureCount = trebleMeasureLayouts.length > bassMeasureLayouts.length 
                ? trebleMeasureLayouts.length 
                : bassMeasureLayouts.length;
            
            final syncedMeasureWidths = <double>[];
            final syncedSystemWidths = <double>[];
            for (int i = 0; i < measureCount; i++) {
              final trebleWidth = i < trebleMeasureLayouts.length 
                  ? trebleMeasureLayouts[i].minWidth 
                  : 0.0;
              final bassWidth = i < bassMeasureLayouts.length 
                  ? bassMeasureLayouts[i].minWidth 
                  : 0.0;
              syncedMeasureWidths.add(trebleWidth > bassWidth ? trebleWidth : bassWidth);
              
              // Also sync system elements width (clef, key sig, etc.)
              // This ensures notes start at the same X position across staves
              final trebleSystemWidth = i < trebleMeasureLayouts.length 
                  ? trebleMeasureLayouts[i].systemElementsWidth 
                  : 0.0;
              final bassSystemWidth = i < bassMeasureLayouts.length 
                  ? bassMeasureLayouts[i].systemElementsWidth 
                  : 0.0;
              syncedSystemWidths.add(trebleSystemWidth > bassSystemWidth ? trebleSystemWidth : bassSystemWidth);
            }
            
            // PASS 2: Layout both staves with constrained measure widths
            final trebleLayout = LayoutEngine(
              widget.trebleStaff,
              availableWidth: constraints.maxWidth,
              staffSpace: widget.staffSpace,
              metadata: _metadata,
            );
            
            final bassLayout = isSingleStaff ? null : LayoutEngine(
              widget.bassStaff!,
              availableWidth: constraints.maxWidth,
              staffSpace: widget.staffSpace,
              metadata: _metadata,
            );

            // Pass synced system widths to ensure beat positions align between staves
            final trebleElements = trebleLayout.layoutWithConstraints(
              syncedMeasureWidths, 
              syncedSystemWidths: isSingleStaff ? null : syncedSystemWidths,
            );
            final bassElements = bassLayout?.layoutWithConstraints(
              syncedMeasureWidths, 
              syncedSystemWidths: syncedSystemWidths,
            ) ?? [];

            if (trebleElements.isEmpty && bassElements.isEmpty) {
              return const Center(child: Text('Empty score'));
            }
            
            // Calculate total width from synced measure widths
            final totalMeasureWidth = syncedMeasureWidths.fold(0.0, (a, b) => a + b);
            final totalWidth = totalMeasureWidth + (widget.staffSpace * LayoutEngine.systemMargin * 2);

            // Calculate single staff height for compact grand staff
            final singleStaffHeight = widget.staffSpace * 10;
            
            // Gap between staves (in pixels)
            final gapHeight = widget.staffSpace * widget.staffGap;
            
            // Total height: single staff or two staves with gap
            final totalHeight = isSingleStaff 
                ? singleStaffHeight 
                : (singleStaffHeight + gapHeight + singleStaffHeight);

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: RepaintBoundary(
                child: CustomPaint(
                  size: Size(totalWidth > constraints.maxWidth ? totalWidth : constraints.maxWidth, totalHeight),
                  painter: _GrandStaffPainter(
                    trebleElements: trebleElements,
                    bassElements: bassElements,
                    trebleLayout: trebleLayout,
                    bassLayout: bassLayout,
                    metadata: _metadata,
                    theme: widget.theme,
                    staffSpace: widget.staffSpace,
                    staffGap: widget.staffGap,
                    showBrace: widget.showBrace && !isSingleStaff, // No brace for single staff
                    singleStaffHeight: singleStaffHeight,
                    totalHeight: totalHeight,
                  ),
                ),
              ),
            );
          },
        );
  }
}

class _GrandStaffPainter extends CustomPainter {
  final List<PositionedElement> trebleElements;
  final List<PositionedElement> bassElements;
  final LayoutEngine trebleLayout;
  final LayoutEngine? bassLayout; // Nullable for single staff mode
  final SmuflMetadata metadata;
  final MusicScoreTheme theme;
  final double staffSpace;
  final double staffGap;
  final bool showBrace;
  final double singleStaffHeight;
  final double totalHeight;

  _GrandStaffPainter({
    required this.trebleElements,
    required this.bassElements,
    required this.trebleLayout,
    this.bassLayout, // Optional for single staff mode
    required this.metadata,
    required this.theme,
    required this.staffSpace,
    required this.staffGap,
    required this.showBrace,
    required this.singleStaffHeight,
    required this.totalHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (metadata.isNotLoaded) return;

    // Calculate the offset for the bass staff
    // Treble staff renders from y=0 to y=singleStaffHeight
    // Then there's a gap
    // Bass staff renders from y=singleStaffHeight+gap
    final bassOffset = singleStaffHeight + (staffSpace * staffGap);

    // Create coordinate systems for rendering
    // Both staves use the same baseline setup internally
    // (LayoutEngine uses baseline = staffSpace * 5.0)
    // We just need to match what LayoutEngine expects
    final trebleBaseline = staffSpace * 5.0;
    final trebleCoords = StaffCoordinateSystem(
      staffSpace: staffSpace,
      staffBaseline: Offset(0, trebleBaseline),
    );
    
    final bassCoords = StaffCoordinateSystem(
      staffSpace: staffSpace,
      staffBaseline: Offset(0, trebleBaseline), // Same baseline, we translate canvas
    );

    // Create renderers
    final trebleRenderer = StaffRenderer(
      coordinates: trebleCoords,
      metadata: metadata,
      theme: theme,
    );

    // Draw brace first (behind staves) - only if we have bass staff
    if (showBrace && bassElements.isNotEmpty) {
      final bassOffset = singleStaffHeight + (staffSpace * staffGap);
      _drawBrace(canvas, size, bassOffset);
    }

    // Render treble staff (no translation needed)
    trebleRenderer.renderStaff(
      canvas,
      trebleElements,
      Size(size.width, singleStaffHeight),
      layoutEngine: trebleLayout,
    );

    // Render bass staff only if we have bass elements
    if (bassElements.isNotEmpty && bassLayout != null) {
      final bassOffset = singleStaffHeight + (staffSpace * staffGap);
      final bassRenderer = StaffRenderer(
        coordinates: bassCoords,
        metadata: metadata,
        theme: theme,
      );
      
      // Render bass staff with canvas translation
      canvas.save();
      canvas.translate(0, bassOffset);
      bassRenderer.renderStaff(
        canvas,
        bassElements,
        Size(size.width, singleStaffHeight),
        layoutEngine: bassLayout,
      );
      canvas.restore();
    }
  }

    void _drawBrace(Canvas canvas, Size size, double bassOffset) {
        final trebleBaseline = staffSpace * 5.0;
        final trebleStaffTop = trebleBaseline - 2 * staffSpace;

        final bassBaseline = bassOffset + staffSpace * 5.0;
        final bassStaffBottom = bassBaseline + 2 * staffSpace;

        final braceTop = trebleStaffTop;
        final braceBottom = bassStaffBottom;
        final braceHeight = braceBottom - braceTop;

        // SMuFL brace glyph
        const braceCodepoint = 0xE000;
        final braceChar = String.fromCharCode(braceCodepoint);

        // Get SMuFL bbox in STAFF SPACES (y positive up)
        final bbox = metadata.getGlyphBoundingBox('brace');
        if (bbox == null) {
            _drawBraceFallback(canvas, braceTop, braceBottom, braceHeight);
            return;
        }

        final bboxHeightStaffSpaces = bbox.bBoxNeY - bbox.bBoxSwY;
        if (bboxHeightStaffSpaces <= 0) {
            _drawBraceFallback(canvas, braceTop, braceBottom, braceHeight);
            return;
        }

        // Scale: 1em = 4 staff spaces => pxPerStaffSpace = fontSize / 4
        // Want: bboxHeightStaffSpaces * pxPerStaffSpace == braceHeight
        // => fontSize = braceHeight * 4 / bboxHeightStaffSpaces
        final fontSize = braceHeight * 4.0 / bboxHeightStaffSpaces;
        final pxPerStaffSpace = fontSize / 4.0;

        final textPainter = TextPainter(
            text: TextSpan(
            text: braceChar,
            style: TextStyle(
                fontFamily: 'Bravura',
                fontSize: fontSize,
                color: theme.staffLineColor,
            ),
            ),
            textDirection: TextDirection.ltr,
        )..layout();

        // IMPORTANT: get baseline inside the layout box
        final lines = textPainter.computeLineMetrics();
        final baselinePx = lines.isNotEmpty ? lines.first.baseline : 0.0;

        // Align bbox top to braceTop using baseline + SMuFL bbox
        final braceX = 2.0;

        // Optional: align bbox left edge to braceX
        final paintX = braceX - (bbox.bBoxSwX * pxPerStaffSpace);

        // Deterministic Y placement (this is the fix)
        final paintY = braceTop - baselinePx + (bbox.bBoxNeY * pxPerStaffSpace);

        // Debug: draw where bbox *actually* lands
        final debug = Paint()
            ..color = const Color(0x4000FF00)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2;

        final bboxLeft = paintX + (bbox.bBoxSwX * pxPerStaffSpace);
        final bboxRight = paintX + (bbox.bBoxNeX * pxPerStaffSpace);
        final bboxTop = paintY + baselinePx - (bbox.bBoxNeY * pxPerStaffSpace);
        final bboxBottom = paintY + baselinePx - (bbox.bBoxSwY * pxPerStaffSpace);

        //canvas.drawRect(Rect.fromLTRB(bboxLeft, bboxTop, bboxRight, bboxBottom), debug);

        textPainter.paint(canvas, Offset(paintX, paintY));

        // Connecting line
        final linePaint = Paint()
            ..color = theme.barlineColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5;

        final lineX = paintX + textPainter.width + 2;
        canvas.drawLine(Offset(lineX, braceTop), Offset(lineX, braceBottom), linePaint);
    }


  void _drawBraceFallback(Canvas canvas, double braceTop, double braceBottom, double braceHeight) {
    const braceCodepoint = 0xE000;
    final braceChar = String.fromCharCode(braceCodepoint);
    
    final textStyle = TextStyle(
      fontFamily: 'Bravura',
      fontSize: braceHeight,
      color: theme.staffLineColor,
    );

    final textPainter = TextPainter(
      text: TextSpan(text: braceChar, style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    final braceX = 2.0;
    final braceCenter = (braceTop + braceBottom) / 2;
    final braceY = braceCenter - (textPainter.height / 2);

    textPainter.paint(canvas, Offset(braceX, braceY));

    // Draw vertical connecting line
    final linePaint = Paint()
      ..color = theme.barlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final lineX = braceX + textPainter.width + 2;
    canvas.drawLine(Offset(lineX, braceTop), Offset(lineX, braceBottom), linePaint);
  }

  @override
  bool shouldRepaint(covariant _GrandStaffPainter oldDelegate) {
    return oldDelegate.trebleElements.length != trebleElements.length ||
        oldDelegate.bassElements.length != bassElements.length ||
        oldDelegate.theme != theme ||
        oldDelegate.staffSpace != staffSpace ||
        oldDelegate.staffGap != staffGap;
  }
}

/// Painter for wrapped (multi-system) grand staff layout
class _WrappedGrandStaffPainter extends CustomPainter {
  final Staff trebleStaff;
  final Staff? bassStaff; // Nullable for single staff mode
  final SmuflMetadata metadata;
  final MusicScoreTheme theme;
  final double staffSpace;
  final double staffGap;
  final bool showBrace;
  final double singleStaffHeight;
  final double grandStaffHeight;
  final double systemSpacing;
  final List<List<int>> systemMeasures;
  final List<double> allMeasureWidths;
  final double availableWidth;

  _WrappedGrandStaffPainter({
    required this.trebleStaff,
    this.bassStaff, // Optional for single staff mode
    required this.metadata,
    required this.theme,
    required this.staffSpace,
    required this.staffGap,
    required this.showBrace,
    required this.singleStaffHeight,
    required this.grandStaffHeight,
    required this.systemSpacing,
    required this.systemMeasures,
    required this.allMeasureWidths,
    required this.availableWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (metadata.isNotLoaded) return;
    
    final isSingleStaff = bassStaff == null;
    final marginSpace = staffSpace * LayoutEngine.systemMargin;
    var currentY = staffSpace; // Top padding
    
    // Render each system
    for (int systemIndex = 0; systemIndex < systemMeasures.length; systemIndex++) {
      final measureIndices = systemMeasures[systemIndex];
      if (measureIndices.isEmpty) continue;
      
      // Extract measures for this system
      final trebleMeasures = <Measure>[];
      final bassMeasures = <Measure>[];
      
      for (final idx in measureIndices) {
        if (idx < trebleStaff.measures.length) {
          trebleMeasures.add(trebleStaff.measures[idx]);
        }
        if (!isSingleStaff && idx < bassStaff!.measures.length) {
          bassMeasures.add(bassStaff!.measures[idx]);
        }
      }
      
      // Create temporary staffs for this system
      final trebleSystemStaff = Staff();
      final bassSystemStaff = Staff();
      
      // Get the original clef, key sig from the first measure of each staff
      Clef? originalTrebleClef;
      KeySignature? originalTrebleKeySig;
      TimeSignature? originalTrebleTimeSig;
      Clef? originalBassClef;
      KeySignature? originalBassKeySig;
      TimeSignature? originalBassTimeSig;
      
      if (trebleStaff.measures.isNotEmpty) {
        for (final elem in trebleStaff.measures[0].elements) {
          if (elem is Clef) originalTrebleClef = elem;
          if (elem is KeySignature) originalTrebleKeySig = elem;
          if (elem is TimeSignature) originalTrebleTimeSig = elem;
        }
      }
      if (!isSingleStaff && bassStaff!.measures.isNotEmpty) {
        for (final elem in bassStaff!.measures[0].elements) {
          if (elem is Clef) originalBassClef = elem;
          if (elem is KeySignature) originalBassKeySig = elem;
          if (elem is TimeSignature) originalBassTimeSig = elem;
        }
      }
      
      // Build treble staff for this system
      for (int i = 0; i < trebleMeasures.length; i++) {
        final measure = trebleMeasures[i];
        final newMeasure = Measure();
        
        // For first measure of each system, ALWAYS add clef and key sig
        if (i == 0) {
          // Always add clef
          if (originalTrebleClef != null) {
            newMeasure.add(Clef(clefType: originalTrebleClef.clefType));
          }
          // Always add key signature
          if (originalTrebleKeySig != null) {
            newMeasure.add(KeySignature(originalTrebleKeySig.count));
          }
          // Only add time sig on first system
          if (systemIndex == 0 && originalTrebleTimeSig != null) {
            newMeasure.add(TimeSignature(
              numerator: originalTrebleTimeSig.numerator, 
              denominator: originalTrebleTimeSig.denominator,
            ));
          }
        }
        
        // Copy all elements from original measure, skipping system elements for first measure
        for (final elem in measure.elements) {
          if (i == 0 && (elem is Clef || elem is KeySignature || elem is TimeSignature)) continue;
          newMeasure.add(elem);
        }
        
        trebleSystemStaff.add(newMeasure);
      }
      
      // Build bass staff for this system (only if we have bass staff)
      if (!isSingleStaff) {
        for (int i = 0; i < bassMeasures.length; i++) {
          final measure = bassMeasures[i];
          final newMeasure = Measure();
          
          // For first measure of each system, ALWAYS add clef and key sig
          if (i == 0) {
            // Always add clef
            if (originalBassClef != null) {
              newMeasure.add(Clef(clefType: originalBassClef.clefType));
            }
            // Always add key signature
            if (originalBassKeySig != null) {
              newMeasure.add(KeySignature(originalBassKeySig.count));
            }
            // Only add time sig on first system
            if (systemIndex == 0 && originalBassTimeSig != null) {
              newMeasure.add(TimeSignature(
                numerator: originalBassTimeSig.numerator, 
                denominator: originalBassTimeSig.denominator,
              ));
            }
          }
          
          // Copy all elements from original measure, skipping system elements for first measure
          for (final elem in measure.elements) {
            if (i == 0 && (elem is Clef || elem is KeySignature || elem is TimeSignature)) continue;
            newMeasure.add(elem);
          }
          
          bassSystemStaff.add(newMeasure);
        }
      }
      
      // Get synced measure widths for just this system
      final systemMeasureWidths = <double>[];
      for (final idx in measureIndices) {
        if (idx < allMeasureWidths.length) {
          systemMeasureWidths.add(allMeasureWidths[idx]);
        }
      }
      
      // Layout this system
      // Only the last system should have a final barline
      final isFinalSystem = systemIndex == systemMeasures.length - 1;
      
      final trebleLayout = LayoutEngine(
        trebleSystemStaff,
        availableWidth: availableWidth,
        staffSpace: staffSpace,
        metadata: metadata,
      );
      
      final bassLayout = isSingleStaff ? null : LayoutEngine(
        bassSystemStaff,
        availableWidth: availableWidth,
        staffSpace: staffSpace,
        metadata: metadata,
      );
      
      // Calculate synced system widths for this system's measures
      List<double>? syncedSystemWidths;
      if (!isSingleStaff) {
        final trebleMeasureLayouts = trebleLayout.calculateMeasureLayouts();
        final bassMeasureLayouts = bassLayout!.calculateMeasureLayouts();
        
        syncedSystemWidths = <double>[];
        final measureCountInSystem = trebleMeasureLayouts.length > bassMeasureLayouts.length 
            ? trebleMeasureLayouts.length 
            : bassMeasureLayouts.length;
            
        for (int i = 0; i < measureCountInSystem; i++) {
          final trebleSystemWidth = i < trebleMeasureLayouts.length 
              ? trebleMeasureLayouts[i].systemElementsWidth 
              : 0.0;
          final bassSystemWidth = i < bassMeasureLayouts.length 
              ? bassMeasureLayouts[i].systemElementsWidth 
              : 0.0;
          syncedSystemWidths.add(trebleSystemWidth > bassSystemWidth ? trebleSystemWidth : bassSystemWidth);
        }
      }
      
      final trebleElements = trebleLayout.layoutWithConstraints(
        systemMeasureWidths, 
        syncedSystemWidths: syncedSystemWidths,
        isFinalSystem: isFinalSystem,
      );
      final bassElements = bassLayout?.layoutWithConstraints(
        systemMeasureWidths, 
        syncedSystemWidths: syncedSystemWidths,
        isFinalSystem: isFinalSystem,
      ) ?? [];
      
      // Calculate bass offset
      final bassOffset = singleStaffHeight + (staffSpace * staffGap);
      
      // Create coordinate systems
      final trebleBaseline = staffSpace * 5.0;
      final trebleCoords = StaffCoordinateSystem(
        staffSpace: staffSpace,
        staffBaseline: Offset(0, trebleBaseline),
      );
      
      // Create renderers
      final trebleRenderer = StaffRenderer(
        coordinates: trebleCoords,
        metadata: metadata,
        theme: theme,
      );
      
      // Translate to current system position
      canvas.save();
      canvas.translate(0, currentY);
      
      // Draw brace (only if we have bass staff)
      if (showBrace && !isSingleStaff) {
        _drawBrace(canvas, bassOffset);
      }
      
      // Render treble staff
      trebleRenderer.renderStaff(
        canvas,
        trebleElements,
        Size(availableWidth, singleStaffHeight),
        layoutEngine: trebleLayout,
      );
      
      // Render bass staff (only if we have bass elements)
      if (!isSingleStaff && bassElements.isNotEmpty && bassLayout != null) {
        final bassCoords = StaffCoordinateSystem(
          staffSpace: staffSpace,
          staffBaseline: Offset(0, trebleBaseline),
        );
        
        final bassRenderer = StaffRenderer(
          coordinates: bassCoords,
          metadata: metadata,
          theme: theme,
        );
        
        canvas.save();
        canvas.translate(0, bassOffset);
        bassRenderer.renderStaff(
          canvas,
          bassElements,
          Size(availableWidth, singleStaffHeight),
          layoutEngine: bassLayout,
        );
        canvas.restore();
      }
      
      canvas.restore();
      
      // Move to next system
      currentY += grandStaffHeight + systemSpacing;
    }
  }
  
  void _drawBrace(Canvas canvas, double bassOffset) {
    final trebleBaseline = staffSpace * 5.0;
    final trebleStaffTop = trebleBaseline - 2 * staffSpace;
    
    final bassBaseline = bassOffset + staffSpace * 5.0;
    final bassStaffBottom = bassBaseline + 2 * staffSpace;
    
    final braceTop = trebleStaffTop;
    final braceBottom = bassStaffBottom;
    final braceHeight = braceBottom - braceTop;
    
    const braceCodepoint = 0xE000;
    final braceChar = String.fromCharCode(braceCodepoint);
    
    final bbox = metadata.getGlyphBoundingBox('brace');
    if (bbox == null) {
      _drawBraceFallback(canvas, braceTop, braceBottom, braceHeight);
      return;
    }
    
    final bboxHeightStaffSpaces = bbox.bBoxNeY - bbox.bBoxSwY;
    if (bboxHeightStaffSpaces <= 0) {
      _drawBraceFallback(canvas, braceTop, braceBottom, braceHeight);
      return;
    }
    
    final fontSize = braceHeight * 4.0 / bboxHeightStaffSpaces;
    final pxPerStaffSpace = fontSize / 4.0;
    
    final textPainter = TextPainter(
      text: TextSpan(
        text: braceChar,
        style: TextStyle(
          fontFamily: 'Bravura',
          fontSize: fontSize,
          color: theme.staffLineColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    
    final lines = textPainter.computeLineMetrics();
    final baselinePx = lines.isNotEmpty ? lines.first.baseline : 0.0;
    
    final braceX = 2.0;
    final paintX = braceX - (bbox.bBoxSwX * pxPerStaffSpace);
    final paintY = braceTop - baselinePx + (bbox.bBoxNeY * pxPerStaffSpace);
    
    textPainter.paint(canvas, Offset(paintX, paintY));
    
    final linePaint = Paint()
      ..color = theme.barlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    
    final lineX = paintX + textPainter.width + 2;
    canvas.drawLine(Offset(lineX, braceTop), Offset(lineX, braceBottom), linePaint);
  }
  
  void _drawBraceFallback(Canvas canvas, double braceTop, double braceBottom, double braceHeight) {
    const braceCodepoint = 0xE000;
    final braceChar = String.fromCharCode(braceCodepoint);
    
    final textStyle = TextStyle(
      fontFamily: 'Bravura',
      fontSize: braceHeight,
      color: theme.staffLineColor,
    );
    
    final textPainter = TextPainter(
      text: TextSpan(text: braceChar, style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    
    final braceX = 2.0;
    final braceCenter = (braceTop + braceBottom) / 2;
    final braceY = braceCenter - (textPainter.height / 2);
    
    textPainter.paint(canvas, Offset(braceX, braceY));
    
    final linePaint = Paint()
      ..color = theme.barlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    
    final lineX = braceX + textPainter.width + 2;
    canvas.drawLine(Offset(lineX, braceTop), Offset(lineX, braceBottom), linePaint);
  }
  
  @override
  bool shouldRepaint(covariant _WrappedGrandStaffPainter oldDelegate) {
    return oldDelegate.systemMeasures.length != systemMeasures.length ||
        oldDelegate.theme != theme ||
        oldDelegate.staffSpace != staffSpace;
  }
}

/// Extension to get the total height of the grand staff widget
extension MusicGrandStaffHeight on MusicGrandStaff {
  /// Calculate the expected height for this grand staff configuration
  double get expectedHeight {
    final singleStaffHeight = staffSpace * 10;
    final gapHeight = staffSpace * staffGap;
    return singleStaffHeight + gapHeight + singleStaffHeight;
  }
}