import os
import sys
from reportlab.lib.pagesizes import letter
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak, KeepTogether, HRFlowable, Image
)
from reportlab.pdfgen import canvas

class NumberedCanvas(canvas.Canvas):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._saved_page_states = []

    def showPage(self):
        self._saved_page_states.append(dict(self.__dict__))
        self._startPage()

    def save(self):
        num_pages = len(self._saved_page_states)
        for state in self._saved_page_states:
            self.__dict__.update(state)
            self.draw_page_decorations(num_pages)
            super().showPage()
        super().save()

    def draw_page_decorations(self, page_count):
        self.saveState()
        self.setFont("Helvetica-Bold", 8)
        self.setFillColor(colors.HexColor("#475569"))
        
        # Header (Pages 2+)
        if self._pageNumber > 1:
            self.drawString(54, letter[1] - 32, "FIRESIGHT — NASA Space Apps Challenge 2026")
            self.setFont("Helvetica", 8)
            self.setFillColor(colors.HexColor("#64748B"))
            self.drawString(250, letter[1] - 32, "|  Feature Expansion & Winning Roadmap")
            self.drawRightString(letter[0] - 54, letter[1] - 32, "Team CedX")
            self.setStrokeColor(colors.HexColor("#E2E8F0"))
            self.setLineWidth(0.6)
            self.line(54, letter[1] - 36, letter[0] - 54, letter[1] - 36)

        # Footer (All pages)
        self.setStrokeColor(colors.HexColor("#E2E8F0"))
        self.setLineWidth(0.6)
        self.line(54, 40, letter[0] - 54, 40)
        
        self.setFont("Helvetica", 8)
        self.setFillColor(colors.HexColor("#64748B"))
        self.drawString(54, 28, "Harmonization of MODIS & VIIRS Hot Spots  ·  Team CedX  ·  Open Source")
        page_str = f"Page {self._pageNumber} of {page_count}"
        self.drawRightString(letter[0] - 54, 28, page_str)
        self.restoreState()

def build_pdf(output_path):
    doc = SimpleDocTemplate(
        output_path,
        pagesize=letter,
        leftMargin=50,
        rightMargin=50,
        topMargin=46,
        bottomMargin=46
    )

    styles = getSampleStyleSheet()
    
    # Custom Brand Palette
    c_primary = colors.HexColor("#0F172A")    # Deep slate
    c_ember = colors.HexColor("#EA580C")      # Flame Ember
    c_amber = colors.HexColor("#D97706")      # Warm amber
    c_teal = colors.HexColor("#0F766E")       # Deep teal
    c_body = colors.HexColor("#1E293B")       # Crisp body charcoal
    c_muted = colors.HexColor("#64748B")      # Muted grey
    c_card_bg = colors.HexColor("#F8FAFC")    # Light slate
    c_alert_bg = colors.HexColor("#FFF7ED")   # Warm orange tint
    c_blue_bg = colors.HexColor("#EFF6FF")    # Ice blue tint
    c_border = colors.HexColor("#CBD5E1")     # Clean border

    title_style = ParagraphStyle(
        'DocTitle',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=20,
        leading=23,
        textColor=c_primary
    )
    
    subtitle_style = ParagraphStyle(
        'DocSubtitle',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=10.5,
        leading=14,
        textColor=c_ember,
        spaceAfter=2
    )

    meta_style = ParagraphStyle(
        'DocMeta',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=8,
        leading=11,
        textColor=c_muted
    )

    h1_style = ParagraphStyle(
        'Heading1_Custom',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=13,
        leading=16,
        textColor=c_primary,
        spaceBefore=8,
        spaceAfter=4,
        keepWithNext=True
    )

    h2_style = ParagraphStyle(
        'Heading2_Custom',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=10,
        leading=13,
        textColor=c_ember,
        spaceBefore=5,
        spaceAfter=2,
        keepWithNext=True
    )

    body_style = ParagraphStyle(
        'Body_Custom',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=8.5,
        leading=11.8,
        textColor=c_body,
        spaceAfter=4
    )

    callout_style = ParagraphStyle(
        'Callout_Text',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=8.2,
        leading=11.2,
        textColor=c_body
    )

    table_header = ParagraphStyle(
        'TableHeader',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=8.2,
        leading=10.5,
        textColor=colors.white
    )

    table_body = ParagraphStyle(
        'TableBody',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=7.8,
        leading=10.2,
        textColor=c_body
    )

    story = []

    # =============================================================
    # PAGE 1: TITLE, AUDIT & SPACE APPS JUDGING ALIGNMENT
    # =============================================================
    logo_path = 'assets/brand/logo.png'
    logo_img = Image(logo_path, width=44, height=44) if os.path.exists(logo_path) else Paragraph("🔥", title_style)
    
    header_data = [
        [
            logo_img,
            [
                Paragraph("FIRESIGHT — STRATEGIC FEATURE ROADMAP", title_style),
                Paragraph("<b>NASA Space Apps Challenge 2026</b> &nbsp;·&nbsp; <i>Harmonization of MODIS and VIIRS Hot Spots</i>", subtitle_style),
                Paragraph("Team <b>CedX</b> &nbsp;|&nbsp; Author: @Omar Abdallah &nbsp;|&nbsp; Comprehensive Review & Strategic Blueprint &nbsp;|&nbsp; Nov 2026", meta_style)
            ]
        ]
    ]
    header_table = Table(header_data, colWidths=[50, 462])
    header_table.setStyle(TableStyle([
        ('VALIGN', (0,0), (-1,-1), 'MIDDLE'),
        ('LEFTPADDING', (0,0), (-1,-1), 0),
        ('RIGHTPADDING', (0,0), (-1,-1), 0),
        ('TOPPADDING', (0,0), (-1,-1), 0),
        ('BOTTOMPADDING', (0,0), (-1,-1), 0),
    ]))
    story.append(header_table)
    story.append(Spacer(1, 6))
    story.append(HRFlowable(width="100%", thickness=1.5, color=c_ember, spaceAfter=8))

    story.append(Paragraph("1. Technical Audit: Where Firesight Excels Today", h1_style))
    story.append(Paragraph(
        "Firesight is already operating at an advanced production tier compared to typical hackathon entries: "
        "a full-stack Flutter app connected to a live deployed backend (<code>firesight.coding-now.online</code>), "
        "25 years of harmonized MODIS and VIIRS active fire history across Mediterranean basins (Portugal, Greece, Lebanon, Cyprus), "
        "leave-one-year-out mathematical validation (reducing yearly error from 61% to 6%), Canadian Fire Weather Index (FWI) forecasting, "
        "crowdsourced compass smoke triangulation, offline disk caching, and full English + Arabic RTL support backed by 100 automated tests. "
        "This document details the exact feature enhancements required to maximize scores across NASA's official judging criteria.",
        body_style
    ))
    story.append(Spacer(1, 4))

    story.append(Paragraph("2. NASA Space Apps Judging Rubric & Score Maximization", h1_style))
    criteria_data = [
        [Paragraph("Judging Criterion", table_header), Paragraph("Weight", table_header), Paragraph("Current App Capability", table_header), Paragraph("Winning Leap (Features to Add)", table_header)],
        [
            Paragraph("<b>Relevance to Challenge</b>", table_body),
            Paragraph("25%", table_body),
            Paragraph("Harmonized 2000–2026 cell-day baseline; eliminated the 2012 MODIS-to-VIIRS seam.", table_body),
            Paragraph("<b>'Cost of Bad Data' Simulator:</b> Expose the false +310% fire panic caused by raw uncalibrated data.", table_body)
        ],
        [
            Paragraph("<b>NASA Data & Science</b>", table_body),
            Paragraph("25%", table_body),
            Paragraph("FIRMS MODIS + VIIRS (SNPP, NOAA-20, NOAA-21), GIBS corrected reflectance.", table_body),
            Paragraph("<b>Multi-NASA Fusion:</b> Integrate NASA SMAP (soil/fuel dryness) & GEOS-FP (smoke/PM2.5 plume).", table_body)
        ],
        [
            Paragraph("<b>Impact & Viability</b>", table_body),
            Paragraph("20%", table_body),
            Paragraph("Early alerts, safe burn planner, escape routes avoiding fire downwind cone.", table_body),
            Paragraph("<b>Satellite Overpass Predictor</b> & <b>1-Tap Civil Defence Incident Brief (PDF)</b>.", table_body)
        ],
        [
            Paragraph("<b>Creativity & Innovation</b>", table_body),
            Paragraph("15%", table_body),
            Paragraph("Crowd-sourced smoke compass triangulation intersecting user bearings.", table_body),
            Paragraph("<b>AR Horizon Pinpoint</b> & <b>Offline Mesh Emergency SOS</b> when cell towers burn down.", table_body)
        ],
        [
            Paragraph("<b>Presentation & Execution</b>", table_body),
            Paragraph("15%", table_body),
            Paragraph("Working Flutter app, Arabic RTL, 39 mobile tests, 61 backend tests.", table_body),
            Paragraph("<b>1-Click Judge Showcase Tour</b> to guarantee judges experience the best flows in under 90 seconds.", table_body)
        ],
    ]
    t_crit = Table(criteria_data, colWidths=[100, 42, 185, 185])
    t_crit.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), c_primary),
        ('ALIGN', (1,0), (1,-1), 'CENTER'),
        ('VALIGN', (0,0), (-1,-1), 'TOP'),
        ('GRID', (0,0), (-1,-1), 0.5, c_border),
        ('ROWBACKGROUNDS', (0,1), (-1,-1), [colors.white, c_card_bg]),
        ('TOPPADDING', (0,0), (-1,-1), 4),
        ('BOTTOMPADDING', (0,0), (-1,-1), 4),
    ]))
    story.append(t_crit)
    story.append(Spacer(1, 8))

    audit_box = [
        [Paragraph(
            "<b>Key Hackathon Insight:</b> Hackathon judges don't just ask <i>'Does the code work?'</i> — they ask <i>'Does this solve a critical problem that NASA cares about, and does it communicate the science clearly?'</i> "
            "By implementing the top-tier features outlined in this roadmap, Firesight transforms from a competent technical tool into an inspiring, globally competitive submission.",
            callout_style
        )]
    ]
    t_audit = Table(audit_box, colWidths=[512])
    t_audit.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,-1), c_blue_bg),
        ('BOX', (0,0), (-1,-1), 1, colors.HexColor("#3B82F6")),
        ('PADDING', (0,0), (-1,-1), 6),
    ]))
    story.append(t_audit)

    story.append(PageBreak())

    # =============================================================
    # PAGE 2: PILLAR 1 (HARMONIZATION) & PILLAR 2 (MULTI-NASA FUSION)
    # =============================================================
    story.append(Paragraph("3. Deepening the Core Science: MODIS & VIIRS Harmonization", h1_style))
    story.append(Paragraph(
        "Harmonization must not remain an invisible backend algorithm. To win this specific challenge, "
        "Firesight must make the mathematical necessity of sensor calibration unforgettable for judges and decision-makers.",
        body_style
    ))

    # Feature 1
    story.append(Paragraph("Feature 1: Interactive Policy Simulator — 'The Cost of Bad Data'", h2_style))
    f1_box = [
        [Paragraph(
            "<b>Concept:</b> Add an interactive toggle on the Today and Calendar screens: <i>'Policy Maker View: Raw vs Harmonized'</i>.<br/>"
            "<b>The Scientific Reality:</b> In 2012, higher-resolution VIIRS (375m) joined MODIS (1km), causing raw active fire detections in Greece and Lebanon to surge by <b>~310%</b>. "
            "If an environment ministry or civil defence agency uses raw satellite data, they conclude that wildfire frequency skyrocketed, "
            "triggering panic, misdirected municipal budgets, and false declarations of policy failure. <br/>"
            "<b>App Interface:</b> Tapping 'Raw View' displays an urgent banner: <i>'RAW DATA ARTIFACT: 2012 displays a false +310% explosion. "
            "Firesight Harmonization reveals 2012 was actually a normal median season (1.08x baseline).'</i> "
            "This delivers an immediate <i>'Aha!'</i> moment for judges on why this hackathon challenge exists.",
            callout_style
        )]
    ]
    t_f1 = Table(f1_box, colWidths=[512])
    t_f1.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,-1), c_alert_bg),
        ('BOX', (0,0), (-1,-1), 1, c_ember),
        ('PADDING', (0,0), (-1,-1), 6),
    ]))
    story.append(t_f1)
    story.append(Spacer(1, 4))

    # Feature 2
    story.append(Paragraph("Feature 2: Climate Phenology Shift & Season Length Expansion", h2_style))
    story.append(Paragraph(
        "<b>Concept:</b> Raw data cannot track fire season shifts because earlier years missed small shoulder-season fires. "
        "With CedX's 25-year harmonized baseline, Firesight visualizes <b>season boundary expansion</b>: "
        "<i>'Mediterranean fire seasons now ignite an average of 12 days earlier (June) and persist 19 days later (late November) compared to the 2000–2005 baseline.'</i> "
        "This connects the sensor harmonization mandate directly to IPCC climate adaptation discourse.",
        body_style
    ))

    # Feature 3
    story.append(Paragraph("Feature 3: FRP (Fire Radiative Power) Harmonization & Carbon Emissions", h2_style))
    story.append(Paragraph(
        "<b>Concept:</b> Active fire counts indicate frequency, but Fire Radiative Power (FRP in Megawatts) reflects <b>combustion intensity and carbon emissions</b>. "
        "By applying standard atmospheric emission factors (Wooster et al., 0.368 kg biomass burnt per MJ of radiative energy), "
        "Firesight converts detected hotspot FRP into: (1) Megawatt thermal energy output, (2) Estimated metric tons of biomass consumed, and "
        "(3) Tons of CO2 and fine particulate (PM2.5) released into the air. This bridges Earth observation with public health.",
        body_style
    ))
    story.append(Spacer(1, 6))

    # Pillar 2: Multi-NASA Fusion
    story.append(Paragraph("4. Multi-NASA Earth Science Dataset Synergy", h1_style))
    story.append(Paragraph(
        "NASA judges heavily favor projects that fuse multiple Earth Observation missions into a coherent solution.",
        body_style
    ))

    datasets_data = [
        [Paragraph("NASA Mission / Product", table_header), Paragraph("Data & Spatial Scale", table_header), Paragraph("Operational Integration in Firesight", table_header)],
        [
            Paragraph("<b>NASA SMAP</b><br/>(Soil Moisture Active Passive)", table_body),
            Paragraph("Surface & root-zone soil moisture (9 km grid)", table_body),
            Paragraph("<b>Live Fuel Moisture Index:</b> Satellite microwave moisture directly measures vegetation water stress, replacing rough weather estimates in the Burn Planner with real underbrush flashpoint risk.", table_body)
        ],
        [
            Paragraph("<b>NASA GEOS-FP / MERRA-2</b><br/>(Aerosol & Atmospheric Flux)", table_body),
            Paragraph("Aerosol Optical Depth (AOD) & surface PM2.5", table_body),
            Paragraph("<b>Downwind Smoke Plume Overlay:</b> Renders 12-hour smoke dispersion polygons on the Map tab, issuing proactive health warnings for residents with respiratory conditions.", table_body)
        ],
        [
            Paragraph("<b>NASA SEDAC GPW</b><br/>(Gridded Population of World)", table_body),
            Paragraph("Global human settlement density (1 km grid)", table_body),
            Paragraph("<b>Population-at-Risk Metric:</b> For every active fire cluster, calculates the exact civilian headcount living within the downwind danger buffer (e.g. <i>'3,400 people exposed'</i>).", table_body)
        ],
        [
            Paragraph("<b>NASA GEDI / Landsat</b><br/>(Canopy Height & Land Cover)", table_body),
            Paragraph("Canopy structure & fuel biomass density", table_body),
            Paragraph("<b>Fuel Load Classification:</b> Discerns pine forest (extreme crown fire risk) from olive groves and scrubland, providing realistic rate-of-spread modeling for emergency escapes.", table_body)
        ],
    ]
    t_data = Table(datasets_data, colWidths=[115, 110, 287])
    t_data.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), c_primary),
        ('VALIGN', (0,0), (-1,-1), 'TOP'),
        ('GRID', (0,0), (-1,-1), 0.5, c_border),
        ('ROWBACKGROUNDS', (0,1), (-1,-1), [colors.white, c_card_bg]),
        ('TOPPADDING', (0,0), (-1,-1), 3.5),
        ('BOTTOMPADDING', (0,0), (-1,-1), 3.5),
    ]))
    story.append(t_data)

    story.append(PageBreak())

    # =============================================================
    # PAGE 3: PILLAR 3 (MOBILE SUPERPOWERS) & PILLAR 4 (CIVIC TOOLS)
    # =============================================================
    story.append(Paragraph("5. Mobile-First Operational Superpowers", h1_style))
    story.append(Paragraph(
        "Firesight's primary edge is that it lives on a mobile device in the field. "
        "The following capabilities leverage native smartphone sensors to provide tools impossible on a desktop.",
        body_style
    ))

    # Feature 4
    story.append(Paragraph("Feature 4: 'Next Eye in the Sky' — Satellite Overpass Predictor", h2_style))
    story.append(Paragraph(
        "<b>The Problem:</b> Polar-orbiting satellites do not hover continuously; they cross overhead at predictable sun-synchronous times (Terra ~10:30 AM/PM, Aqua/VIIRS ~1:30 PM/AM). "
        "When a citizen spots smoke at 11:15 AM, satellite confirmation cannot appear until after the 1:30 PM pass. Without context, users assume the system is failing.<br/>"
        "<b>The Solution:</b> A dynamic overpass countdown widget on the Map and Report screens: "
        "<i>'🛰️ Next Eye in the Sky: NOAA-20 VIIRS overpass in 1h 12m (13:28 local). Next FIRMS refresh: ~13:45.'</i> "
        "This demonstrates advanced domain understanding of orbital mechanics to NASA evaluators.",
        body_style
    ))

    # Feature 5
    story.append(Paragraph("Feature 5: AR (Augmented Reality) Horizon Smoke & Fire Pinpoint", h2_style))
    story.append(Paragraph(
        "<b>The Concept:</b> Firesight already includes compass bearing alignment (<code>compass_aim.dart</code>). "
        "Binding device orientation with the live camera feed allows users to point their phone at a distant mountain ridge. "
        "The camera screen renders an AR reticle showing magnetic bearing, lines of sight, and satellite hotspot markers pinned "
        "over the physical horizon (<i>'Active VIIRS hotspot 5.8 km behind this ridge'</i>). Highly cinematic for the hackathon video.",
        body_style
    ))

    # Feature 6
    story.append(Paragraph("Feature 6: Zero-Cellular BLE Mesh Emergency Network ('Burned Tower Relay')", h2_style))
    story.append(Paragraph(
        "<b>The Problem:</b> In destructive wildfires, telecommunication towers frequently burn down, lose electricity, or suffer network overload.<br/>"
        "<b>The Solution:</b> Offline Peer-to-Peer Relay over Bluetooth Low Energy (BLE) and local Wi-Fi Direct. "
        "Even when mobile networks are completely severed, phones running Firesight relay cached evacuation routes, active danger perimeters, "
        "and SOS civilian beacons from device to device across refugee assembly points and rural valleys.",
        body_style
    ))

    # Feature 7
    story.append(Paragraph("Feature 7: On-Device Edge AI Smoke & Fire Photo Pre-Classifier", h2_style))
    story.append(Paragraph(
        "<b>The Concept:</b> When users attach a photo in <code>report_screen.dart</code>, run a lightweight on-device vision model (MobileNetV4 / TFLite) "
        "before network transmission. The model outputs: (1) Smoke verification confidence (e.g. 94%), and (2) Smoke color diagnosis "
        "(white/grey = wildland brush; black/dense = structural or tire fire). Prevents troll spam and saves uplink bandwidth during crises.",
        body_style
    ))
    story.append(Spacer(1, 4))

    # Pillar 4: Civic Impact
    story.append(Paragraph("6. Civic Impact & Emergency Operational Tools", h1_style))
    story.append(Paragraph(
        "Hackathon judges prioritize projects that provide tangible value to emergency responders and local communities.",
        body_style
    ))

    # Feature 8
    story.append(Paragraph("Feature 8: 1-Tap 'Civil Defence Incident Situation Brief' (Exportable PDF)", h2_style))
    story.append(Paragraph(
        "<b>The Feature:</b> An <i>'Export Incident Brief'</i> button on the Zone Report and Safety screens generating a standardized, print-ready PDF containing: "
        "<br/>• Visual incident map displaying satellite hotspots, confidence flags, and FRP intensity."
        "<br/>• Crowdsourced smoke triangulation bearings and estimated fire ignition circle."
        "<br/>• Canadian Fire Weather Index components (FFMC, DMC, DC, ISI, BUI, wind velocity)."
        "<br/>• Identified OpenStreetMap water points (hydrants, reservoirs) and wind-safe egress routes."
        "<br/><b>Civic Impact:</b> Village mayors, civil defence squads (Lebanon 125, Greece 199), and volunteer brigades receive an authoritative operational briefing in seconds.",
        body_style
    ))

    # Feature 9
    story.append(Paragraph("Feature 9: Agricultural Smart Burn Permit & Smoke Drift Calculator", h2_style))
    story.append(Paragraph(
        "<b>The Problem:</b> A major percentage of Mediterranean wildfires are triggered by farmers burning agricultural pruning residues.<br/>"
        "<b>The Solution:</b> Upgrade the Burn Planner into an official digital advisory certificate. "
        "Farmers enter crop type (olive branches, wheat stubble) and pit dimensions; the app calculates an amber/green <i>'Safe Burn Window Certificate'</i> "
        "accounting for wind gusts, relative humidity, and atmospheric smoke dispersion.",
        body_style
    ))

    story.append(PageBreak())

    # =============================================================
    # PAGE 4: JUDGE PLAYBOOK & IMPLEMENTATION ROADMAP
    # =============================================================
    story.append(Paragraph("7. Hackathon Pitch Strategy & Judge Experience", h1_style))
    story.append(Paragraph(
        "Judges evaluate dozens of projects in a rush. Ensuring they instantly grasp your value within 90 seconds is critical.",
        body_style
    ))

    # Feature 10
    story.append(Paragraph("Feature 10: 1-Click 'Space Apps Judge Showcase Tour' (90-Second Walkthrough)", h2_style))
    tour_box = [
        [Paragraph(
            "<b>Must-Build Hackathon Feature:</b> Add an explicit badge in Onboarding and Settings: <i>'🎯 Space Apps Judge Tour (90s)'</i>.<br/>"
            "If an international judge evaluates Firesight from a region with zero fires today, they risk missing dynamic screens. "
            "Tapping this button initiates a guided 3-act simulated wildfire scenario:<br/>"
            "<b>Act 1: The Alert</b> — Simulated satellite detection in Attica/Mount Lebanon triggers an instant high-risk alert.<br/>"
            "<b>Act 2: Citizen Verification</b> — Two simulated smoke compass reports cross on the map, calculating fire coordinates.<br/>"
            "<b>Act 3: Escape & The Seam</b> — Dynamic evacuation route calculates around the fire smoke cone, concluding at the 2012 Seam simulator.<br/>"
            "Guarantees every evaluator experiences the full breadth of your engineering in under two minutes.",
            callout_style
        )]
    ]
    t_tour = Table(tour_box, colWidths=[512])
    t_tour.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,-1), c_blue_bg),
        ('BOX', (0,0), (-1,-1), 1, colors.HexColor("#3B82F6")),
        ('PADDING', (0,0), (-1,-1), 6),
    ]))
    story.append(t_tour)
    story.append(Spacer(1, 4))

    story.append(Paragraph("The Winning 3-Minute Video Pitch Structure", h2_style))
    story.append(Paragraph(
        "<b>0:00–0:30 The Hook:</b> <i>'In 2012, satellite records showed a sudden 300% explosion in Mediterranean fires. Was our region burning down? No. NASA upgraded from MODIS to VIIRS. Without harmonization, satellite data lies.'</i><br/>"
        "<b>0:30–1:15 The Science:</b> Explain the 25-year harmonized baseline, cell-day calibration, and leave-one-year-out mathematical validation.<br/>"
        "<b>1:15–2:15 The Live Product:</b> Showcase the mobile app: FIRMS live detection, smoke compass triangulation, and escape routing.<br/>"
        "<b>2:15–3:00 Real-World Impact:</b> Civil defence integration, Arabic bilingual accessibility, and community disaster resilience.",
        body_style
    ))
    story.append(Spacer(1, 6))

    story.append(Paragraph("8. Actionable Implementation Prioritization Matrix", h1_style))
    story.append(Paragraph(
        "Strategic feature roadmap ranked by implementation effort versus judging scoring impact:",
        body_style
    ))

    matrix_data = [
        [Paragraph("Feature / Enhancement", table_header), Paragraph("Target Phase", table_header), Paragraph("Implementation Effort", table_header), Paragraph("Judging Impact Score", table_header)],
        [
            Paragraph("<b>'Cost of Bad Data' Policy Simulator</b>", table_body),
            Paragraph("Immediate (Pre-Submission)", table_body),
            Paragraph("Low (Reuses existing raw vs harmonized counts)", table_body),
            Paragraph("⭐⭐⭐⭐⭐ (Critical for challenge theme)", table_body)
        ],
        [
            Paragraph("<b>'Next Eye in the Sky' Satellite Pass</b>", table_body),
            Paragraph("Immediate (Pre-Submission)", table_body),
            Paragraph("Low (Calculated from known orbit times)", table_body),
            Paragraph("⭐⭐⭐⭐⭐ (Proves deep NASA expertise)", table_body)
        ],
        [
            Paragraph("<b>1-Click Space Apps Judge Tour</b>", table_body),
            Paragraph("Immediate (Pre-Submission)", table_body),
            Paragraph("Medium (UI state scenario walkthrough)", table_body),
            Paragraph("⭐⭐⭐⭐⭐ (Guarantees evaluator engagement)", table_body)
        ],
        [
            Paragraph("<b>FRP Energy & Carbon Estimator</b>", table_body),
            Paragraph("Immediate (Pre-Submission)", table_body),
            Paragraph("Low (Math conversion on FIRMS FRP)", table_body),
            Paragraph("⭐⭐⭐⭐ (Broadens scientific depth)", table_body)
        ],
        [
            Paragraph("<b>1-Tap Civil Defence Brief (PDF)</b>", table_body),
            Paragraph("Phase 2 (Post-Hackathon)", table_body),
            Paragraph("Medium (PDF generation engine)", table_body),
            Paragraph("⭐⭐⭐⭐ (Institutional viability)", table_body)
        ],
        [
            Paragraph("<b>NASA SMAP Soil & GEOS-FP Smoke</b>", table_body),
            Paragraph("Phase 2 (Post-Hackathon)", table_body),
            Paragraph("High (Backend data ingestion pipeline)", table_body),
            Paragraph("⭐⭐⭐⭐⭐ (Multi-mission synergy)", table_body)
        ],
        [
            Paragraph("<b>AR Horizon Pinpoint & BLE Mesh</b>", table_body),
            Paragraph("Phase 3 (Vision Roadmap)", table_body),
            Paragraph("High (Native sensor and mesh plugins)", table_body),
            Paragraph("⭐⭐⭐⭐ (Novel mobile differentiation)", table_body)
        ],
    ]
    t_mat = Table(matrix_data, colWidths=[142, 110, 130, 130])
    t_mat.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), c_primary),
        ('VALIGN', (0,0), (-1,-1), 'MIDDLE'),
        ('GRID', (0,0), (-1,-1), 0.5, c_border),
        ('ROWBACKGROUNDS', (0,1), (-1,-1), [colors.white, c_card_bg]),
        ('TOPPADDING', (0,0), (-1,-1), 3.5),
        ('BOTTOMPADDING', (0,0), (-1,-1), 3.5),
    ]))
    story.append(t_mat)
    story.append(Spacer(1, 6))

    concl_box = [
        [Paragraph(
            "<b>Final Verdict:</b> Team CedX has built a powerhouse application with exceptional technical depth. "
            "By spotlighting the <b>'Cost of Bad Data'</b>, adding the <b>'Satellite Overpass Countdown'</b>, "
            "and equipping judges with the <b>'90s Showcase Tour'</b>, Firesight has every ingredient to claim top global honors at NASA Space Apps 2026.",
            callout_style
        )]
    ]
    t_concl = Table(concl_box, colWidths=[512])
    t_concl.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,-1), c_alert_bg),
        ('BOX', (0,0), (-1,-1), 1, c_ember),
        ('PADDING', (0,0), (-1,-1), 6),
    ]))
    story.append(t_concl)

    doc.build(story, canvasmaker=NumberedCanvas)
    print(f"PDF built successfully at: {output_path}")

if __name__ == '__main__':
    out_file = sys.argv[1] if len(sys.argv) > 1 else 'Firesight_Feature_Expansion_Roadmap.pdf'
    build_pdf(out_file)
