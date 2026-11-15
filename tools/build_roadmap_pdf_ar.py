import os
import sys
import arabic_reshaper
from bidi.algorithm import get_display
from reportlab.lib.pagesizes import letter
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak, HRFlowable, Image
)
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

# Register Arabic TrueType Fonts from Windows Fonts directory
font_dir = r'C:\Windows\Fonts'
arial_path = os.path.join(font_dir, 'arial.ttf')
arial_bold_path = os.path.join(font_dir, 'arialbd.ttf')

pdfmetrics.registerFont(TTFont('ArabicFont', arial_path))
pdfmetrics.registerFont(TTFont('ArabicFont-Bold', arial_bold_path))
pdfmetrics.registerFontFamily('ArabicFont', normal='ArabicFont', bold='ArabicFont-Bold')

def ar(text):
    """Reshape and BiDi a single line of Arabic text."""
    if not text:
        return ""
    reshaped = arabic_reshaper.reshape(text)
    return get_display(reshaped)

def ar_clean_para(text, max_width, font_name='ArabicFont', font_size=8.5):
    """
    Splits text into lines fitting max_width based on font metrics,
    reshapes and applies BiDi to each line, and returns lines joined by <br/>.
    """
    if not text:
        return ""
    paragraphs = text.split('\n')
    out_paras = []
    for p in paragraphs:
        p = p.strip()
        if not p:
            continue
        words = p.split()
        lines = []
        curr = []
        for w in words:
            trial = ' '.join(curr + [w])
            reshaped = arabic_reshaper.reshape(trial)
            width = pdfmetrics.stringWidth(reshaped, font_name, font_size)
            if width <= max_width or not curr:
                curr.append(w)
            else:
                lines.append(' '.join(curr))
                curr = [w]
        if curr:
            lines.append(' '.join(curr))
            
        bidi_lines = [get_display(arabic_reshaper.reshape(l)) for l in lines]
        out_paras.append('<br/>'.join(bidi_lines))
    return '<br/>'.join(out_paras)

class NumberedArabicCanvas(canvas.Canvas):
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
            self.draw_decorations(num_pages)
            super().showPage()
        super().save()

    def draw_decorations(self, page_count):
        self.saveState()
        self.setFont("ArabicFont-Bold", 8)
        self.setFillColor(colors.HexColor("#475569"))
        
        # Header (Pages 2+)
        if self._pageNumber > 1:
            hdr_right = ar("فايرسايت (Firesight) — تحدي ناسا لتطبيقات الفضاء 2026")
            hdr_sub = ar("|  خارطة طريق تطوير الميزات واستراتيجية الفوز")
            hdr_left = ar("فريق CedX")
            
            self.drawRightString(letter[0] - 50, letter[1] - 32, hdr_right)
            self.setFont("ArabicFont", 8)
            self.setFillColor(colors.HexColor("#64748B"))
            self.drawRightString(letter[0] - 250, letter[1] - 32, hdr_sub)
            self.drawString(50, letter[1] - 32, hdr_left)
            
            self.setStrokeColor(colors.HexColor("#CBD5E1"))
            self.setLineWidth(0.6)
            self.line(50, letter[1] - 36, letter[0] - 50, letter[1] - 36)

        # Footer (All pages)
        self.setStrokeColor(colors.HexColor("#CBD5E1"))
        self.setLineWidth(0.6)
        self.line(50, 40, letter[0] - 50, 40)
        
        self.setFont("ArabicFont", 8)
        self.setFillColor(colors.HexColor("#64748B"))
        ftr_right = ar("مواءمة ومطابقة بيانات MODIS و VIIRS  ·  فريق CedX  ·  مشروع مفتوح المصدر")
        page_str = ar(f"صفحة {self._pageNumber} من {page_count}")
        
        self.drawRightString(letter[0] - 50, 27, ftr_right)
        self.drawString(50, 27, page_str)
        self.restoreState()

def build_arabic_pdf(output_path):
    doc = SimpleDocTemplate(
        output_path,
        pagesize=letter,
        leftMargin=50,
        rightMargin=50,
        topMargin=46,
        bottomMargin=46
    )

    styles = getSampleStyleSheet()
    
    # Custom Brand Colors
    c_primary = colors.HexColor("#0F172A")    # Deep slate
    c_ember = colors.HexColor("#EA580C")      # Flame Ember
    c_amber = colors.HexColor("#D97706")      # Warm amber
    c_body = colors.HexColor("#1E293B")       # Dark charcoal text
    c_muted = colors.HexColor("#64748B")      # Muted grey
    c_card_bg = colors.HexColor("#F8FAFC")    # Slate tint
    c_alert_bg = colors.HexColor("#FFF7ED")   # Warm orange alert
    c_blue_bg = colors.HexColor("#EFF6FF")    # Ice blue tint
    c_border = colors.HexColor("#CBD5E1")     # Clean border

    title_style = ParagraphStyle(
        'DocTitleAr',
        parent=styles['Normal'],
        fontName='ArabicFont-Bold',
        fontSize=18,
        leading=22,
        alignment=2, # TA_RIGHT
        textColor=c_primary
    )
    
    subtitle_style = ParagraphStyle(
        'DocSubtitleAr',
        parent=styles['Normal'],
        fontName='ArabicFont-Bold',
        fontSize=10,
        leading=13.5,
        alignment=2,
        textColor=c_ember,
        spaceAfter=2
    )

    meta_style = ParagraphStyle(
        'DocMetaAr',
        parent=styles['Normal'],
        fontName='ArabicFont',
        fontSize=7.8,
        leading=11,
        alignment=2,
        textColor=c_muted
    )

    h1_style = ParagraphStyle(
        'Heading1_Ar',
        parent=styles['Normal'],
        fontName='ArabicFont-Bold',
        fontSize=12,
        leading=15,
        alignment=2,
        textColor=c_primary,
        spaceBefore=7,
        spaceAfter=3,
        keepWithNext=True
    )

    h2_style = ParagraphStyle(
        'Heading2_Ar',
        parent=styles['Normal'],
        fontName='ArabicFont-Bold',
        fontSize=9.5,
        leading=12.5,
        alignment=2,
        textColor=c_ember,
        spaceBefore=4.5,
        spaceAfter=1.5,
        keepWithNext=True
    )

    body_style = ParagraphStyle(
        'Body_Ar',
        parent=styles['Normal'],
        fontName='ArabicFont',
        fontSize=8.2,
        leading=11.4,
        alignment=2,
        textColor=c_body,
        spaceAfter=3.5
    )

    callout_style = ParagraphStyle(
        'Callout_Ar',
        parent=styles['Normal'],
        fontName='ArabicFont',
        fontSize=7.8,
        leading=10.8,
        alignment=2,
        textColor=c_body
    )

    table_header = ParagraphStyle(
        'TableHeaderAr',
        parent=styles['Normal'],
        fontName='ArabicFont-Bold',
        fontSize=7.8,
        leading=10.2,
        alignment=2,
        textColor=colors.white
    )

    table_body = ParagraphStyle(
        'TableBodyAr',
        parent=styles['Normal'],
        fontName='ArabicFont',
        fontSize=7.4,
        leading=9.8,
        alignment=2,
        textColor=c_body
    )

    story = []

    # =============================================================
    # PAGE 1: TITLE, AUDIT & NASA SPACE APPS JUDGING ALIGNMENT
    # =============================================================
    logo_path = 'assets/brand/logo.png'
    logo_img = Image(logo_path, width=44, height=44) if os.path.exists(logo_path) else Paragraph("🔥", title_style)
    
    header_data = [
        [
            [
                Paragraph(ar("فايرسايت (Firesight) — خارطة طريق الميزات الاستراتيجية"), title_style),
                Paragraph(ar("تحدي ناسا لتطبيقات الفضاء 2026  ·  مواءمة ومطابقة رصدات مستشعرات MODIS و VIIRS"), subtitle_style),
                Paragraph(ar("فريق CedX  |  إعداد: عمر عبد الله (@Omar Abdallah)  |  مراجعة شاملة وخطة عمل الفوز بالتحدي  |  نوفمبر 2026"), meta_style)
            ],
            logo_img
        ]
    ]
    header_table = Table(header_data, colWidths=[462, 50])
    header_table.setStyle(TableStyle([
        ('VALIGN', (0,0), (-1,-1), 'MIDDLE'),
        ('LEFTPADDING', (0,0), (-1,-1), 0),
        ('RIGHTPADDING', (0,0), (-1,-1), 0),
        ('TOPPADDING', (0,0), (-1,-1), 0),
        ('BOTTOMPADDING', (0,0), (-1,-1), 0),
    ]))
    story.append(header_table)
    story.append(Spacer(1, 5))
    story.append(HRFlowable(width="100%", thickness=1.5, color=c_ember, spaceAfter=6))

    story.append(Paragraph(ar("1. التدقيق التقني: أين يبرز تطبيق فايرسايت اليوم؟"), h1_style))
    p1_audit = (
        "يحتل تطبيق فايرسايت حالياً مكانة متقدمة تضعه ضمن نخبة مشاريع الهاكاثون من الناحية الهندسية والتطبيقية: "
        "تطبيق هاتف ذكي متكامل مبني بتقنية فلاتر مرتبط بخادم سحابي حي يعمل على مدار الساعة (firesight.coding-now.online)، "
        "سجل تاريخي مواءم وموحد يمتد لـ 25 عاماً من رصدات أقمار ناسا (MODIS و VIIRS) لدول حوض البحر المتوسط المعرضة للحرائق (لبنان، اليونان، قبرص، البرتغال)، "
        "خوارزمية تحقق رياضي دقيقة (Leave-one-year-out) قللت نسبة الخطأ السنوي من 61% إلى 6%، نظام توقع مؤشر طقس الحرائق الكندي (FWI)، "
        "تثليث دخان الحرائق عبر البوصلة المغناطيسية للهاتف، تخزين محلي كامل للعمل في انقطاع الإنترنت، ودعم عربي كامل بنمط RTL مع 100 اختبار آلي شامل. "
        "تحدد هذه الوثيقة الميزات الاستراتيجية الإضافية المقترحة لضمان حصد العلامة الكاملة في معايير تحكيم ناسا الرسمية."
    )
    story.append(Paragraph(ar_clean_para(p1_audit, 512, font_size=8.2), body_style))
    story.append(Spacer(1, 3))

    story.append(Paragraph(ar("2. معايير تقييم حكام ناسا وكيفية تحقيق الدرجة القصوى"), h1_style))
    
    # RTL Table: Columns ordered Right to Left:
    # Col 3 (Right): المعيار
    # Col 2: الوزن
    # Col 1: إنجاز فايرسايت الحالي
    # Col 0 (Left): الميزة المطلوبة للفوز
    criteria_data = [
        [
            Paragraph(ar("الميزة الإضافية المطلوبة للفوز بالجائزة"), table_header),
            Paragraph(ar("إنجاز فايرسايت الحالي في التطبيق"), table_header),
            Paragraph(ar("الوزن"), table_header),
            Paragraph(ar("معيار تحكيم ناسا"), table_header)
        ],
        [
            Paragraph(ar_clean_para("محاكي تكلفة البيانات الخاطئة: إبراز خطر الذعر الوهمي (+310%) الناتج عن البيانات الخام وتصحيحه.", 185, font_size=7.4), table_body),
            Paragraph(ar_clean_para("سجل تاريخي 2000–2026 مواءم ومعاير، وحل فجوة انتقال المستشعرات في عام 2012.", 185, font_size=7.4), table_body),
            Paragraph(ar("25%"), table_body),
            Paragraph(ar("مطابقة التحدي العلمي"), table_body)
        ],
        [
            Paragraph(ar_clean_para("دمج منظومة أقمار ناسا: ربط قمر SMAP (رطوبة الوقود والتربة) ونموذج GEOS-FP (سحب الدخان).", 185, font_size=7.4), table_body),
            Paragraph(ar_clean_para("رصدات NASA FIRMS (أربعة أقمار) وصور NASA GIBS المصححة إشعاعياً للأرض.", 185, font_size=7.4), table_body),
            Paragraph(ar("25%"), table_body),
            Paragraph(ar("بيانات ناسا والعمق العلمي"), table_body)
        ],
        [
            Paragraph(ar_clean_para("متنبئ عبور أقمار ناسا مع تقرير الموقف العملياتي المطبوع للدفاع المدني بصيغة PDF.", 185, font_size=7.4), table_body),
            Paragraph(ar_clean_para("إنذارات مبكرة، مخطط الحرق الزراعي، ومسارات إخلاء آمنة تتفادى مخروط خطر الحريق.", 185, font_size=7.4), table_body),
            Paragraph(ar("20%"), table_body),
            Paragraph(ar("الأثر المجتمعي والجدوى"), table_body)
        ],
        [
            Paragraph(ar_clean_para("الواقع المعزز (AR) لتحديد خط الأفق مع شبكة الطوارئ المحلية (BLE Mesh) عند انقطاع الشبكات.", 185, font_size=7.4), table_body),
            Paragraph(ar_clean_para("تثليث الدخان المجتمعي بحساب تقاطع زوايا بوصلات الهواتف مع دائرة الارتياب.", 185, font_size=7.4), table_body),
            Paragraph(ar("15%"), table_body),
            Paragraph(ar("الابتكار والإبداع"), table_body)
        ],
        [
            Paragraph(ar_clean_para("جولة الحكام السريعة بضغطة واحدة: لتمكين الحكام من تجربة السيناريو الكامل في 90 ثانية.", 185, font_size=7.4), table_body),
            Paragraph(ar_clean_para("تطبيق فلاتر عالي الجودة، واجهة عربية كاملة، 100 اختبار برمجي ناجح على الكود.", 185, font_size=7.4), table_body),
            Paragraph(ar("15%"), table_body),
            Paragraph(ar("العرض التقديمي والتنفيذ"), table_body)
        ],
    ]
    t_crit = Table(criteria_data, colWidths=[185, 185, 42, 100])
    t_crit.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), c_primary),
        ('ALIGN', (2,0), (2,-1), 'CENTER'),
        ('VALIGN', (0,0), (-1,-1), 'TOP'),
        ('GRID', (0,0), (-1,-1), 0.5, c_border),
        ('ROWBACKGROUNDS', (0,1), (-1,-1), [colors.white, c_card_bg]),
        ('TOPPADDING', (0,0), (-1,-1), 3),
        ('BOTTOMPADDING', (0,0), (-1,-1), 3),
    ]))
    story.append(t_crit)
    story.append(Spacer(1, 5))

    audit_box_text = (
        "رؤية استراتيجية للفوز: لجان تحكيم ناسا لا تسأل فقط 'هل الكود البرمجي يعمل؟' بل تبحث عن: "
        "'هل يحل هذا المشروع مشكلة وطنية وعالمية حقيقية، وهل يبسط علوم الفضاء المعقدة لصانع القرار والإنسان العادي؟' "
        "عبر إضافة الميزات التالية، يتحول فايرسايت من أداة تقنية متقنة إلى مشروع استثنائي مرشح للجوائز العالمية."
    )
    t_audit = Table([[Paragraph(ar_clean_para(audit_box_text, 500, font_size=7.8), callout_style)]], colWidths=[512])
    t_audit.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,-1), c_blue_bg),
        ('BOX', (0,0), (-1,-1), 1, colors.HexColor("#3B82F6")),
        ('PADDING', (0,0), (-1,-1), 5),
    ]))
    story.append(t_audit)

    story.append(PageBreak())

    # =============================================================
    # PAGE 2: PILLAR 1 (HARMONIZATION) & PILLAR 2 (MULTI-NASA FUSION)
    # =============================================================
    story.append(Paragraph(ar("3. تعميق الجانب العلمي لمواءمة المستشعرات (Core Challenge Science)"), h1_style))
    p2_intro = (
        "يجب ألا تظل خوارزمية المواءمة مجرد معامل رياضي خفي في الخلفية. للفوز بهذا التحدي المتخصص، "
        "يجب على فايرسايت تجسيد أهمية مواءمة بيانات ناسا بشكل تفاعلي مبهر يراه الحكام وصناع القرار بأعينهم."
    )
    story.append(Paragraph(ar_clean_para(p2_intro, 512, font_size=8.2), body_style))

    # Feature 1
    story.append(Paragraph(ar("الميزة 1: محاكي القرارات وصناع السياسات — 'تكلفة البيانات الخاطئة' (The Cost of Bad Data)"), h2_style))
    f1_text = (
        "المفهوم: إضافة مفتاح تبديل تفاعلي في شاشتي اليوم والتقويم: 'منظور صانع القرار: البيانات الخام مقابل المواءمة'.\n"
        "الواقع العلمي: في عام 2012 انضم مستشعر VIIRS بدقة 375 متراً إلى مستشعر MODIS بدقة 1 كم، مما أدى لقفزة وهمية في عدد الرصدات بلغت +310% في اليونان ولبنان. "
        "إذا اعتمدت وزارة البيئة أو الدفاع المدني على البيانات غير المعالجة، فستستنتج خطأً أن حرائق الغابات خرجت عن السيطرة أو أن خطط الإخماد فشلت، "
        "مما يسبب هلعاً عاماً وإهداراً للميزانيات الوطنية في قرارات خاطئة.\n"
        "واجهة التطبيق: عند الضغط على 'البيانات الخام'، يظهر تنبيه أحمر: 'تحذير: البيانات الخام تظهر قفزة وهمية بنسبة +310%! "
        "بينما تثبت خوارزمية فايرسايت أن عام 2012 كان موسماً طبيعياً تماماً (1.08 ضعف المتوسط العام).' "
        "هذا يمنح الحكام إدراكاً فورياً للأهمية المصيرية لهذا التحدي."
    )
    t_f1 = Table([[Paragraph(ar_clean_para(f1_text, 500, font_size=7.8), callout_style)]], colWidths=[512])
    t_f1.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,-1), c_alert_bg),
        ('BOX', (0,0), (-1,-1), 1, c_ember),
        ('PADDING', (0,0), (-1,-1), 5),
    ]))
    story.append(t_f1)
    story.append(Spacer(1, 3))

    # Feature 2
    story.append(Paragraph(ar("الميزة 2: مؤشر تمدد موسم الحرائق وظاهرة التغير المناخي (Climate Phenology Shift)"), h2_style))
    f2_text = (
        "المفهوم: تعجز البيانات الخام عن كشف التغير المناخي لأن السنوات القديمة كانت تفوت الحرائق الصغيرة. "
        "بفضل خط الأساس المواءم لـ 25 عاماً، يوضح فايرسايت تمدد حدود موسم الحرائق: "
        "'أصبح موسم حرائق حوض المتوسط يبدأ أبكر بمعدل 12 يوماً (يونيو) ويستمر متأخراً بمعدل 19 يوماً (أواخر نوفمبر) مقارنة بفترة 2000–2005.' "
        "هذا يربط مواءمة المستشعرات مباشرة بتقارير الهيئة الحكومية الدولية المعنية بتغير المناخ (IPCC)."
    )
    story.append(Paragraph(ar_clean_para(f2_text, 512, font_size=8.2), body_style))

    # Feature 3
    story.append(Paragraph(ar("الميزة 3: مواءمة الطاقة الإشعاعية (FRP) وتقدير انبعاثات الكربون والجسيمات"), h2_style))
    f3_text = (
        "المفهوم: عدد النقاط الساخنة يعبر عن التكرار فقط، بينما تقيس الطاقة الإشعاعية (FRP بالميجاواط) شدة الاحتراق الحقيقية. "
        "بتطبيق معادلات الفيزياء الجوية المعتمدة (Wooster et al.، حرق 0.368 كجم من الكتلة الحيوية لكل ميجاجول طاقة)، "
        "يحول فايرسايت الميجاواط إلى: (1) إجمالي الطاقة الحرارية، (2) أطنان الكتلة الحيوية المحترقة، و "
        "(3) انبعاثات غاز CO2 والجسيمات الدقيقة السامة (PM2.5). هذا ينقل بيانات الأقمار الصناعية إلى صلب حماية الصحة العامة."
    )
    story.append(Paragraph(ar_clean_para(f3_text, 512, font_size=8.2), body_style))
    story.append(Spacer(1, 5))

    # Pillar 2: Multi-NASA Fusion
    story.append(Paragraph(ar("4. تكامل بيانات منظومة أقمار ناسا المتعددة (Multi-NASA Synergy)"), h1_style))
    p2_fusion = (
        "تمنح لجان تحكيم ناسا أعلى الدرجات للمشاريع التي تدمج بيانات عدة مهام فضائية لوكالة ناسا في منصة تشغيلية واحدة متناسقة."
    )
    story.append(Paragraph(ar_clean_para(p2_fusion, 512, font_size=8.2), body_style))

    datasets_data = [
        [
            Paragraph(ar("التطبيق العملي والتشغيلي في فايرسايت"), table_header),
            Paragraph(ar("طبيعة البيانات والدقة المكانية"), table_header),
            Paragraph(ar("مهمة ناسا الفضائية / المنتج"), table_header)
        ],
        [
            Paragraph(ar_clean_para("مؤشر رطوبة الوقود الحيوي: قياس رطوبة التربة عبر موجات الميكروويف لتقدير جفاف النباتات وسرعة اشتعال الشجيرات بدقة تفوق التقديرات العادية.", 285, font_size=7.4), table_body),
            Paragraph(ar_clean_para("رطوبة التربة السطحية والجذور بدقة شبكية 9 كم.", 110, font_size=7.4), table_body),
            Paragraph(ar("NASA SMAP\n(رطوبة التربة الحيوية)"), table_body)
        ],
        [
            Paragraph(ar_clean_para("طبقة مسار الدخان المتوقع: رسم مضلع انتشار الدخان لـ 12 ساعة باتجاه الرياح على الخريطة، لتنبيه مرضى الربو والجهاز التنفسي في القرى المجاورة.", 285, font_size=7.4), table_body),
            Paragraph(ar_clean_para("العمق البصري للهباء الجوي وجسيمات PM2.5 السطحية.", 110, font_size=7.4), table_body),
            Paragraph(ar("NASA GEOS-FP / MERRA-2\n(نمذجة الهباء الجوي)"), table_body)
        ],
        [
            Paragraph(ar_clean_para("عداد السكان المعرضين للخطر: حساب التعداد السكاني الفعلي المقيم داخل نطاق وصول الدخان والحرائق النشطة تلقائياً (مثال: '3,400 نسمة معرضون للخطر').", 285, font_size=7.4), table_body),
            Paragraph(ar_clean_para("الكثافة السكانية والتجمعات العمرانية بدقة 1 كم.", 110, font_size=7.4), table_body),
            Paragraph(ar("NASA SEDAC GPW\n(التوزيع السكاني العالمي)"), table_body)
        ],
        [
            Paragraph(ar_clean_para("تصنيف حمولة الوقود النباتي: التمييز بين غابات الصنوبر سريعة الاشتعال الشديد وبساتين الزيتون والأراضي العشبية، لحساب سرعة تقدم ألسنة اللهب بواقعية.", 285, font_size=7.4), table_body),
            Paragraph(ar_clean_para("ارتفاع المظلة الشجرية وكثافة الكتلة الحيوية والغطاء.", 110, font_size=7.4), table_body),
            Paragraph(ar("NASA GEDI / Landsat\n(ديناميكيات الغطاء النباتي)"), table_body)
        ],
    ]
    t_data = Table(datasets_data, colWidths=[287, 110, 115])
    t_data.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), c_primary),
        ('VALIGN', (0,0), (-1,-1), 'TOP'),
        ('GRID', (0,0), (-1,-1), 0.5, c_border),
        ('ROWBACKGROUNDS', (0,1), (-1,-1), [colors.white, c_card_bg]),
        ('TOPPADDING', (0,0), (-1,-1), 3),
        ('BOTTOMPADDING', (0,0), (-1,-1), 3),
    ]))
    story.append(t_data)

    story.append(PageBreak())

    # =============================================================
    # PAGE 3: PILLAR 3 (MOBILE SUPERPOWERS) & PILLAR 4 (CIVIC TOOLS)
    # =============================================================
    story.append(Paragraph(ar("5. قدرات الهاتف الذكي التشغيلية (Mobile-First Superpowers)"), h1_style))
    p3_mobile = (
        "القوة التنافسية الكبرى لتطبيق فايرسايت تكمن في كونه أداة ميدانية في جيب المواطن والمزارع ورجل الإطفاء. "
        "توظف الميزات التالية مستشعرات الهاتف الذكي لتقديم حلول يستحيل تطبيقها على مواقع الويب المكتبية."
    )
    story.append(Paragraph(ar_clean_para(p3_mobile, 512, font_size=8.2), body_style))

    # Feature 4
    story.append(Paragraph(ar("الميزة 4: 'عين الفضاء التالية' — مؤشر العد التنازلي لعبور أقمار ناسا (Overpass Predictor)"), h2_style))
    f4_text = (
        "المشكلة: أقمار المدارات القطبية لا تبقى ثابتة فوق الدولة، بل تعبر في مواعيد مدارية شمسية محددة (Terra ~10:30 صباحاً/مساءً، Aqua/VIIRS ~1:30 ظهراً/ليلاً). "
        "عندما يشاهد مواطن دخاناً الساعة 11:15 صباحاً، لن يظهر التأكيد الفضائي إلا بعد عبور قمر 1:30 ظهراً. عدم معرفة هذا يجعل المستخدمين يظنون أن النظام معطل.\n"
        "الحل: إضافة مؤشر مداري مباشر في شاشتي الخريطة والإبلاغ: "
        "'🛰️ عين الفضاء التالية: عبور قمر NOAA-20 VIIRS خلال ساعة و12 دقيقة (13:28 محلياً). التحديث القادم لـ FIRMS: ~13:45.' "
        "يبرهن هذا على فهم عميق لديناميكيات مدارات أقمار ناسا الصناعية."
    )
    story.append(Paragraph(ar_clean_para(f4_text, 512, font_size=8.2), body_style))

    # Feature 5
    story.append(Paragraph(ar("الميزة 5: التصويب نحو الأفق بالواقع المعزز (AR Horizon Smoke & Fire Pinpoint)"), h2_style))
    f5_text = (
        "المفهوم: يحتوي فايرسايت بالفعل على بوصلة اتجاه الدخان (compass_aim.dart). "
        "بربط مستشعر حركة الهاتف مع كاميرا الجهاز، يوجه المستخدم الهاتف نحو سلاسل الجبال البعيدة. "
        "تعرض الكاميرا شبكة تصويب مع زاوية البوصلة الدقيقة وإسقاط علامات النقاط الساخنة المكتشفة بالقمر الصناعي خلف التلال الواقعية "
        "('نقطة حريق VIIRS نشطة على بعد 5.8 كم خلف هذا الجبل'). ميزة مذهلة بصرياً في فيديو التحكيم."
    )
    story.append(Paragraph(ar_clean_para(f5_text, 512, font_size=8.2), body_style))

    # Feature 6
    story.append(Paragraph(ar("الميزة 6: شبكة الطوارئ المحلية بدون شبكة خلوية (BLE Mesh Emergency Relay)"), h2_style))
    f6_text = (
        "المشكلة: في كوارث الحرائق الكبرى، كثيراً ما تحترق أبراج الاتصالات أو تنقطع عنها الكهرباء أو تصاب بالشلل التام نتيجة الضغط.\n"
        "الحل: بناء شبكة تواصل محلية ند-إلى-ند عبر البلوتوث منخفض الطاقة (BLE) و Wi-Fi Direct. "
        "حتى عند انقطاع شبكات الهاتف المحمول تماماً، تنقل هواتف فايرسايت مسارات الهروب المحفوظة مسبقاً، ونطاقات الخطر المحدثة، "
        "ونداءات الاستغاثة بين المواطنين من هاتف لآخر عبر الوديان ومراكز الإيواء تلقائياً."
    )
    story.append(Paragraph(ar_clean_para(f6_text, 512, font_size=8.2), body_style))

    # Feature 7
    story.append(Paragraph(ar("الميزة 7: التحقق الذكي بالذكاء الاصطناعي على الهاتف (On-Device Edge AI Classifier)"), h2_style))
    f7_text = (
        "المفهوم: عند التقاط صورة في شاشة الإبلاغ (report_screen.dart)، يفحص نموذج رؤية خفيف على الهاتف (MobileNet / TFLite) "
        "الصورة محلياً قبل رفعها. يحدد النموذج: (1) نسبة الثقة بوجود دخان حقيقي (مثال 94%)، و (2) تشخيص لون الدخان "
        "(أبيض/رمادي = حريق أعشاب ونباتات؛ أسود كثيف = حريق مبانٍ أو إطارات أو مواد بترولية). يمنع هذا البلاغات المزيفة ويوفر سرعة الإنترنت أثناء الأزمات."
    )
    story.append(Paragraph(ar_clean_para(f7_text, 512, font_size=8.2), body_style))
    story.append(Spacer(1, 4))

    # Pillar 4: Civic Impact
    story.append(Paragraph(ar("6. الأثر المجتمعي وأدوات الاستجابة للطوارئ (Civic Impact)"), h1_style))
    p3_civic = (
        "تحصد المشاريع المراكز الأولى عندما تتجاوز مرحلة الفكرة النظرية لتصبح أداة لا غنى عنها للدفاع المدني والمجتمعات المحلية."
    )
    story.append(Paragraph(ar_clean_para(p3_civic, 512, font_size=8.2), body_style))

    # Feature 8
    story.append(Paragraph(ar("الميزة 8: تقرير الموقف العملياتي للدفاع المدني بضغطة واحدة (Civil Defence Incident Brief)"), h2_style))
    f8_text = (
        "الميزة: إضافة زر 'تصدير تقرير الموقف' في شاشتي المناطق والسلامة يولد تقريراً رسمياً بصيغة PDF قابلاً للطباعة والمشاركة يشمل:\n"
        "• خريطة الحريق بالأقمار الصناعية مع مستويات الثقة وشدة الطاقة الإشعاعية (FRP).\n"
        "• إحداثيات تثليث دخان المواطنين ودائرة الارتياب التقديرية لبؤرة الاشتعال.\n"
        "• مؤشرات طقس الحرائق الكندية (FFMC, DMC, DC, ISI, BUI) وسرعة واتجاه الرياح.\n"
        "• مصادر المياه القريبة (مآخذ إطفاء، أنهار، بحيرات) ومسارات الإخلاء الآمنة ضد اتجاه الرياح.\n"
        "الأثر: يحصل قادة الدفاع المدني (125 في لبنان، 199 في اليونان) ورؤساء البلديات على وثيقة عملياتية متكاملة في ثوانٍ."
    )
    story.append(Paragraph(ar_clean_para(f8_text, 512, font_size=8.2), body_style))

    # Feature 9
    story.append(Paragraph(ar("الميزة 9: تصريح الحرق الزراعي الذكي وحساب مسار الدخان (Smart Burn Permit)"), h2_style))
    f9_text = (
        "المشكلة: تندلع نسبة كبرى من حرائق المتوسط بسبب قيام المزارعين بحرق مخلفات التقليم الزراعي في أيام خادعة الطقس.\n"
        "الحل: ترقية مخطط الحرق إلى تصريح استشاري ذكي. يدخل المزارع نوع المحصول (أغصان زيتون، قش قمح) وحجم الكومة؛ "
        "فيصدر التطبيق 'شهادة نافذة الحرق الآمن' مع تحديد ساعات الحرق الآمنة ومسافة الأمان المطلوبة عن مصادر المياه."
    )
    story.append(Paragraph(ar_clean_para(f9_text, 512, font_size=8.2), body_style))

    story.append(PageBreak())

    # =============================================================
    # PAGE 4: JUDGE PLAYBOOK & IMPLEMENTATION ROADMAP
    # =============================================================
    story.append(Paragraph(ar("7. استراتيجية العرض التقديمي وتجربة لجنة التحكيم"), h1_style))
    p4_pitch = (
        "تقوم لجان التحكيم بتقييم عشرات المشاريع في وقت ضيق جداً. ضمان إبهارهم وإيصال قيمة عملكم في أول 90 ثانية هو مفتاح الفوز."
    )
    story.append(Paragraph(ar_clean_para(p4_pitch, 512, font_size=8.2), body_style))

    # Feature 10
    story.append(Paragraph(ar("الميزة 10: 'جولة حكام ناسا في 90 ثانية' (1-Click Space Apps Judge Tour)"), h2_style))
    tour_text = (
        "أهم ميزة للهاكاثون: وضع زر بارز في شاشة البداية والإعدادات: '🎯 جولة حكام ناسا السريعة (90 ثانية)'.\n"
        "إذا قام حكم دولي بتقييم التطبيق من دولة لا تشهد حرائق اليوم، فقد تفوته الشاشات التفاعلية الممتلئة بالبيانات. "
        "عند الضغط على هذا الزر، يعيش الحكم سيناريو حريق افتراضي ثلاثي الفصول:\n"
        "الفصل الأول: الإنذار الفضائي — رصد قمر صناعي في جبل لبنان أو اليونان يطلق تنبيهاً لمؤشر FWI المرتفع.\n"
        "الفصل الثاني: التحقق الميداني — تقاطع بلاغي دخان بالبوصلة من مواطنين لرسم بؤرة الحريق على الخريطة.\n"
        "الفصل الثالث: الإخلاء والمواءمة — حساب مسار هروب آمن يتفادى سحابة الدخان، ثم مقارنة فجوة 2012 بالمواءمة.\n"
        "يضمن هذا تجربة كل محكّم لكامل إبداعاتكم البرمجية خلال دقيقة ونصف فقط."
    )
    t_tour = Table([[Paragraph(ar_clean_para(tour_text, 500, font_size=7.8), callout_style)]], colWidths=[512])
    t_tour.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,-1), c_blue_bg),
        ('BOX', (0,0), (-1,-1), 1, colors.HexColor("#3B82F6")),
        ('PADDING', (0,0), (-1,-1), 5),
    ]))
    story.append(t_tour)
    story.append(Spacer(1, 3))

    story.append(Paragraph(ar("هيكل الفيديو التقديمي الفائز (3 دقائق محكمة)"), h2_style))
    pitch_text = (
        "0:00–0:30 الافتتاحية الجاذبة: 'في عام 2012، أظهرت بيانات الأقمار الصناعية انفجاراً مفاجئاً بنسبة 300% في حرائق المتوسط. هل كان حوض المتوسط يحترق فجأة؟ لا. ناسا قامت بترقية المستشعر من MODIS إلى VIIRS. بدون مواءمة دقيقة، فإن بيانات الفضاء تكذب.'\n"
        "0:30–1:15 الأساس العلمي: استعراض السجل المواءم لـ 25 عاماً، وتصحيح انقطاعات الأقمار، والتحقق الرياضي من الخوارزمية.\n"
        "1:15–2:15 الاستعراض الحي: جولة حية سريعة: رصدات FIRMS اللحظية، تثليث الدخان بالبوصلة، ومسارات الإخلاء الآمنة.\n"
        "2:15–3:00 الأثر الإنساني: دعم الدفاع المدني، التعريب واللغة العربية الكاملة، وحماية الأرواح والممتلكات في المتوسط."
    )
    story.append(Paragraph(ar_clean_para(pitch_text, 512, font_size=8.2), body_style))
    story.append(Spacer(1, 5))

    story.append(Paragraph(ar("8. مصفوفة أولويات التنفيذ الاستراتيجية"), h1_style))
    story.append(Paragraph(ar_clean_para("خارطة الطريق مرتبة حسب الجهد البرمجي المطلوب مقابل أثرها المباشر في درجات التحكيم:", 512, font_size=8.2), body_style))

    # RTL Prioritization Table:
    # Col 3 (Right): الميزة
    # Col 2: مرحلة التنفيذ
    # Col 1: الجهد البرمجي
    # Col 0 (Left): الأثر في درجات التحكيم
    matrix_data = [
        [
            Paragraph(ar("الأثر في درجات التحكيم"), table_header),
            Paragraph(ar("الجهد البرمجي المطلوب"), table_header),
            Paragraph(ar("المرحلة الزمنية المقترحة"), table_header),
            Paragraph(ar("الميزة / الإضافة المقترحة"), table_header)
        ],
        [
            Paragraph(ar("⭐⭐⭐⭐⭐ (أساسي لموضوع التحدي)"), table_body),
            Paragraph(ar("منخفض (استثمار بيانات المقارنة الجاهزة)"), table_body),
            Paragraph(ar("فوري (قبل تسليم الهاكاثون)"), table_body),
            Paragraph(ar("محاكي 'تكلفة البيانات الخاطئة'"), table_body)
        ],
        [
            Paragraph(ar("⭐⭐⭐⭐⭐ (يبرز الخبرة بعلوم الفضاء)"), table_body),
            Paragraph(ar("منخفض (حساب مواعيد المدارات الثابتة)"), table_body),
            Paragraph(ar("فوري (قبل تسليم الهاكاثون)"), table_body),
            Paragraph(ar("متنبئ عبور أقمار ناسا (Overpass)"), table_body)
        ],
        [
            Paragraph(ar("⭐⭐⭐⭐⭐ (يضمن انبهار الحكام)"), table_body),
            Paragraph(ar("متوسط (بناء سيناريو تفاعلي بالحالات)"), table_body),
            Paragraph(ar("فوري (قبل تسليم الهاكاثون)"), table_body),
            Paragraph(ar("جولة حكام ناسا السريعة (90 ثانية)"), table_body)
        ],
        [
            Paragraph(ar("⭐⭐⭐⭐ (يعمق البعد البيئي والمناخي)"), table_body),
            Paragraph(ar("منخفض (معادلات تحويل طاقة FRP)"), table_body),
            Paragraph(ar("فوري (قبل تسليم الهاكاثون)"), table_body),
            Paragraph(ar("حساب انبعاثات الكربون والجسيمات"), table_body)
        ],
        [
            Paragraph(ar("⭐⭐⭐⭐ (يثبت الجدوى للمؤسسات)"), table_body),
            Paragraph(ar("متوسط (محرك تصدير ملفات PDF)"), table_body),
            Paragraph(ar("المرحلة الثانية (الإصدار 1.1)"), table_body),
            Paragraph(ar("تقرير الموقف العملياتي للدفاع المدني"), table_body)
        ],
        [
            Paragraph(ar("⭐⭐⭐⭐⭐ (تكامل أسطول ناسا)"), table_body),
            Paragraph(ar("مرتفع (بناء خطوط سحب بيانات جديدة)"), table_body),
            Paragraph(ar("المرحلة الثانية (الإصدار 1.1)"), table_body),
            Paragraph(ar("دمج بيانات SMAP ورادار الدخان"), table_body)
        ],
        [
            Paragraph(ar("⭐⭐⭐⭐ (ابتكار تقني فائق)"), table_body),
            Paragraph(ar("مرتفع (حزم برمجية متقدمة للمستشعرات)"), table_body),
            Paragraph(ar("المرحلة الثالثة (الرؤية المستقبلية)"), table_body),
            Paragraph(ar("الواقع المعزز (AR) وشبكة BLE Mesh"), table_body)
        ],
    ]
    t_mat = Table(matrix_data, colWidths=[130, 130, 110, 142])
    t_mat.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), c_primary),
        ('VALIGN', (0,0), (-1,-1), 'MIDDLE'),
        ('GRID', (0,0), (-1,-1), 0.5, c_border),
        ('ROWBACKGROUNDS', (0,1), (-1,-1), [colors.white, c_card_bg]),
        ('TOPPADDING', (0,0), (-1,-1), 3),
        ('BOTTOMPADDING', (0,0), (-1,-1), 3),
    ]))
    story.append(t_mat)
    story.append(Spacer(1, 5))

    concl_text = (
        "الخلاصة النهائية: يمتلك فريق CedX عملاً استثنائياً بأساس علمي رصين وتطبيق فائق الجودة. "
        "من خلال تسليط الضوء على 'تكلفة البيانات الخاطئة'، وإضافة 'متنبئ عبور أقمار ناسا'، "
        "وتقديم 'جولة الحكام السريعة'، يمتلك تطبيق فايرسايت كافة المقومات لحصد الجائزة العالمية في تحدي ناسا لتطبيقات الفضاء 2026."
    )
    t_concl = Table([[Paragraph(ar_clean_para(concl_text, 500, font_size=7.8), callout_style)]], colWidths=[512])
    t_concl.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,-1), c_alert_bg),
        ('BOX', (0,0), (-1,-1), 1, c_ember),
        ('PADDING', (0,0), (-1,-1), 5),
    ]))
    story.append(t_concl)

    doc.build(story, canvasmaker=NumberedArabicCanvas)
    print(f"Arabic PDF built successfully at: {output_path}")

if __name__ == '__main__':
    out_file = sys.argv[1] if len(sys.argv) > 1 else 'Firesight_Feature_Expansion_Roadmap_AR.pdf'
    build_arabic_pdf(out_file)
