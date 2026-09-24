import UIKit

// Standalone visual exploration. Does not link AetherUI or reproduce a MagicOS renderer.
let ink = UIColor(red: 0.12, green: 0.16, blue: 0.25, alpha: 1)
let accent = UIColor(red: 0.34, green: 0.34, blue: 0.83, alpha: 1)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> UIColor { UIColor(red:r,green:g,blue:b,alpha:a) }

@MainActor final class Canvas: UIView {
    let dark: Bool
    init(dark: Bool) { self.dark = dark; super.init(frame: CGRect(x:0,y:0,width:402,height:874)); isOpaque = true }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ rect: CGRect) {
        guard let c = UIGraphicsGetCurrentContext() else { return }
        let colors = dark ? [color(0.06,0.09,0.20).cgColor,color(0.16,0.16,0.32).cgColor,color(0.06,0.16,0.25).cgColor] : [color(0.94,0.95,1).cgColor,color(0.82,0.86,0.98).cgColor,color(0.89,0.97,0.98).cgColor]
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0,0.52,1])!
        c.drawLinearGradient(gradient,start:CGPoint(x:0,y:0),end:CGPoint(x:350,y:874),options:[.drawsBeforeStartLocation,.drawsAfterEndLocation])
        let glows: [(CGPoint,CGFloat,UIColor)] = dark ? [(CGPoint(x:385,y:360),340,color(0.34,0.24,0.65,0.70)),(CGPoint(x:-40,y:695),340,color(0.05,0.51,0.59,0.42))] : [(CGPoint(x:340,y:340),315,color(0.71,0.55,0.96,0.48)),(CGPoint(x:-30,y:630),315,color(0.42,0.84,0.98,0.48))]
        for (p,r,tint) in glows {
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),colors:[tint.cgColor,tint.withAlphaComponent(0).cgColor] as CFArray,locations:[0,1])!
            c.drawRadialGradient(g,startCenter:p,startRadius:0,endCenter:p,endRadius:r,options:[])
        }
        // Fine arcs and beads make the backdrop's optical treatment readable.
        for i in 0..<4 {
            let p = UIBezierPath(ovalIn:CGRect(x:78+CGFloat(i)*17,y:250+CGFloat(i)*17,width:405,height:405))
            (dark ? UIColor.white.withAlphaComponent(0.07) : UIColor.white.withAlphaComponent(0.42)).setStroke(); p.lineWidth = i == 0 ? 2 : 0.7; p.stroke()
        }
        for (x,y,r) in [(34.0,350.0,7.0),(359.0,661.0,13.0),(308.0,196.0,4.0),(86.0,733.0,4.0)] {
            let p = UIBezierPath(ovalIn:CGRect(x:x,y:y,width:r,height:r)); UIColor.white.withAlphaComponent(dark ? 0.15 : 0.6).setFill(); p.fill()
        }
    }
}

@MainActor final class PreviewController: UIViewController {
    let mode: String
    let stage = UIView(frame:CGRect(x:0,y:0,width:402,height:874))
    var dark: Bool { mode == "dark" }
    var foreground: UIColor { dark ? .white : ink }
    var secondary: UIColor { dark ? color(0.75,0.79,0.90) : color(0.39,0.44,0.56) }
    init(mode: String) { self.mode = mode; super.init(nibName:nil,bundle:nil) }
    required init?(coder: NSCoder) { fatalError() }
    override var preferredStatusBarStyle: UIStatusBarStyle { dark ? .lightContent : .darkContent }
    override func viewDidLoad() {
        super.viewDidLoad(); overrideUserInterfaceStyle = dark ? .dark : .light
        view.addSubview(stage); stage.addSubview(Canvas(dark:dark))
        if mode == "components" { components() } else { chat() }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews(); stage.transform = .identity
        stage.frame = CGRect(x:0,y:0,width:402,height:874)
        stage.transform = CGAffineTransform(scaleX:view.bounds.width/402,y:view.bounds.height/874)
        stage.frame.origin = .zero
    }
    @discardableResult func label(_ text:String,_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ h:CGFloat,_ size:CGFloat = 16,_ weight:UIFont.Weight = .regular,_ tint:UIColor? = nil,_ align:NSTextAlignment = .left,_ parent:UIView? = nil) -> UILabel {
        let l = UILabel(frame:CGRect(x:x,y:y,width:w,height:h)); l.text = text; l.font = .systemFont(ofSize:size,weight:weight); l.textColor = tint ?? foreground; l.textAlignment = align; l.numberOfLines = 0; (parent ?? stage).addSubview(l); return l
    }
    @discardableResult func symbol(_ name:String,_ x:CGFloat,_ y:CGFloat,_ size:CGFloat,_ tint:UIColor? = nil,_ parent:UIView? = nil) -> UIImageView {
        let v = UIImageView(image:UIImage(systemName:name,withConfiguration:UIImage.SymbolConfiguration(pointSize:size-3,weight:.medium)))
        v.frame = CGRect(x:x,y:y,width:size,height:size); v.contentMode = .scaleAspectFit; v.tintColor = tint ?? foreground; (parent ?? stage).addSubview(v); return v
    }
    @discardableResult func glass(_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ h:CGFloat,_ radius:CGFloat,_ tint:UIColor? = nil,_ regular:Bool = false,_ parent:UIView? = nil) -> UIVisualEffectView {
        let e = UIGlassEffect(style:regular ? .regular : .clear); e.isInteractive = true
        e.tintColor = tint ?? (dark ? color(0.30,0.35,0.55,0.08) : UIColor.white.withAlphaComponent(0.12))
        let v = UIVisualEffectView(effect:e); v.frame = CGRect(x:x,y:y,width:w,height:h); v.layer.cornerRadius = radius; v.layer.cornerCurve = .continuous; v.clipsToBounds = true
        v.layer.borderWidth = 0.6; v.layer.borderColor = UIColor.white.withAlphaComponent(dark ? 0.22 : 0.70).cgColor
        let shadow = UIView(frame:v.frame); shadow.layer.cornerRadius = radius; shadow.layer.cornerCurve = .continuous
        shadow.backgroundColor = .clear; shadow.layer.shadowColor = (dark ? UIColor.black : color(0.34,0.38,0.60)).cgColor; shadow.layer.shadowOpacity = dark ? 0.25 : 0.10; shadow.layer.shadowRadius = 14; shadow.layer.shadowOffset = CGSize(width:0,height:7); shadow.layer.shadowPath = UIBezierPath(roundedRect:shadow.bounds,cornerRadius:radius).cgPath
        (parent ?? stage).addSubview(shadow); (parent ?? stage).addSubview(v); return v
    }
    func line(_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ parent:UIView? = nil) { let l = UIView(frame:CGRect(x:x,y:y,width:w,height:0.5)); l.backgroundColor = foreground.withAlphaComponent(0.10); (parent ?? stage).addSubview(l) }
    func tag(_ text:String = "AETHER  /  КОНЦЕПТ") { label(text,24,76,300,15,10,.semibold,secondary).setLetterSpacing(1.8) }
    func components() {
        tag(); label("Components",23,106,300,44,33,.bold)
        label("Новый характер знакомых элементов",24,156,320,23,14,.regular,secondary)
        let more = glass(336,108,43,43,21.5); symbol("ellipsis",11,11,21,nil,more.contentView)
        let seg = glass(23,205,356,48,24)
        let selection = glass(4,4,114,40,20,UIColor.white.withAlphaComponent(0.25),false,seg.contentView)
        label("Все",0,0,114,40,14,.semibold,accent,.center,selection.contentView)
        label("Управление",119,0,118,48,14,.medium,secondary,.center,seg.contentView)
        label("Навигация",238,0,118,48,14,.medium,secondary,.center,seg.contentView)
        label("ИНТЕРФЕЙС",30,280,260,16,10,.semibold,secondary).setLetterSpacing(1.6)
        let group = glass(23,308,356,325,29)
        let rows:[(String,String,String)] = [("Buttons","Кнопки и быстрые действия","hand.tap"),("Context Menu","Превью, реакции, подменю","contextualmenu.and.cursorarrow"),("Segmented Control","Плавное переключение","rectangle.split.3x1"),("Action Sheet","Действия в одном слое","square.stack.3d.up"),("Floating Toolbar","Плавающая навигация","rectangle.bottomthird.inset.filled")]
        for (i,r) in rows.enumerated() {
            let y = CGFloat(i)*65
            symbol(r.2,19,y+19,27,accent,group.contentView)
            label(r.0,61,y+12,251,24,16,.semibold,nil,.left,group.contentView)
            label(r.1,61,y+36,251,17,11,.regular,secondary,.left,group.contentView)
            symbol("chevron.right",326,y+25,13,secondary.withAlphaComponent(0.7),group.contentView)
            if i<4 { line(61,y+65,275,group.contentView) }
        }
        label("БЫСТРЫЕ ДЕЙСТВИЯ",30,660,290,16,10,.semibold,secondary).setLetterSpacing(1.6)
        let b1 = glass(23,688,157,47,23.5); symbol("plus",17,13,21,accent,b1.contentView); label("Создать",48,0,99,47,14,.semibold,accent,.left,b1.contentView)
        let b2 = glass(192,688,120,47,23.5); symbol("square.and.arrow.up",17,13,21,nil,b2.contentView); label("Отправить",45,0,71,47,12,.medium,nil,.left,b2.contentView)
        let b3 = glass(326,688,53,47,23.5); symbol("heart",16,13,21,nil,b3.contentView)
        let tab = glass(23,779,287,63,31.5)
        let active = glass(5,5,72,53,26.5,UIColor.white.withAlphaComponent(0.24),false,tab.contentView)
        symbol("square.grid.2x2",25,7,24,accent,active.contentView); label("UI",0,31,72,15,10,.semibold,accent,.center,active.contentView)
        for (i,n) in ["sparkles","list.bullet.rectangle","gearshape"].enumerated() { let x = CGFloat(i+1)*69+10; symbol(n,x+20,11,24,nil,tab.contentView); label(["States","ListView","Settings"][i],x,38,66,14,9,.medium,nil,.center,tab.contentView) }
        let search = glass(324,779,55,63,28); symbol("magnifyingglass",14,18,28,nil,search.contentView)
    }
    func bubble(_ text:String,_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ h:CGFloat,_ outgoing:Bool = false,_ opacity:CGFloat = 1) {
        let b = UIView(frame:CGRect(x:x,y:y,width:w,height:h)); b.layer.cornerRadius = 21; b.layer.cornerCurve = .continuous
        b.backgroundColor = outgoing ? (dark ? color(0.36,0.31,0.63,0.62) : color(0.76,0.77,0.96,0.65)) : UIColor.white.withAlphaComponent(dark ? 0.10 : 0.50); b.alpha = opacity; stage.addSubview(b)
        label(text,16,10,w-30,h-20,15,.regular,nil,.left,b)
    }
    func chat() {
        tag()
        let back = glass(21,108,43,43,21.5); symbol("chevron.left",12,11,21,nil,back.contentView)
        label("Татьяна Толстая",78,107,250,27,20,.semibold)
        label("была недавно",79,134,230,20,12,.regular,secondary)
        let avatar = glass(336,108,44,44,22); label("ТТ",0,0,44,44,13,.semibold,accent,.center,avatar.contentView)
        label("Сегодня",0,190,402,22,11,.medium,secondary,.center)
        bubble("Привет! Как новый интерфейс?",21,234,282,48)
        bubble("Очень нравится это стекло",123,295,258,49,true)
        bubble("Особенно меню и навигация ✨",21,359,283,51)
        if dark {
            bubble("Сохраним эту идею?",180,424,201,49,true)
            let dim = UIView(frame:stage.bounds); dim.backgroundColor = UIColor.black.withAlphaComponent(0.24); stage.addSubview(dim)
            let sh = glass(18,496,366,278,32,color(0.31,0.35,0.54,0.13))
            label("Действия с сообщением",23,17,300,25,16,.semibold,.white,.left,sh.contentView)
            label("«Сохраним эту идею?»",23,43,300,19,12,.regular,color(0.78,0.81,0.91),.left,sh.contentView)
            line(21,77,324,sh.contentView)
            for (i,row) in [("Ответить","arrowshape.turn.up.left"),("Переслать","arrowshape.turn.up.right"),("Закрепить","pin"),("Удалить сообщение","trash")].enumerated() {
                let y = 82+CGFloat(i)*47; let c:UIColor = i==3 ? color(1,0.53,0.62) : .white
                symbol(row.1,23,y+12,23,c,sh.contentView); label(row.0,64,y,269,47,15,.medium,c,.left,sh.contentView)
                if i<3 { line(64,y+47,281,sh.contentView) }
            }
            let cancel = glass(18,785,366,53,26.5,color(0.36,0.40,0.56,0.16)); label("Отмена",0,0,366,53,16,.semibold,.white,.center,cancel.contentView)
        } else {
            // The original selected content is suppressed while the lifted preview owns it.
            // This prevents duplicate text being refracted behind the preview.
            let scrim = UIView(frame:CGRect(x:0,y:172,width:402,height:590)); scrim.backgroundColor = color(0.52,0.57,0.71,0.08); stage.addSubview(scrim)
            // Detached preview deliberately overlays the dimmed original bubble.
            let lifted = glass(89,422,293,77,23,UIColor.white.withAlphaComponent(0.19))
            label("Да! Смотрится легко и объёмно",17,12,261,40,15,.medium,ink,.left,lifted.contentView)
            label("14:32  ✓✓",20,54,255,13,9,.medium,secondary,.right,lifted.contentView)
            let reactions = glass(162,366,218,45,22.5,nil,true)
            label("❤️     👍     🔥     ✨",0,0,218,45,21,.regular,nil,.center,reactions.contentView)
            let menu = glass(136,511,244,216,26,UIColor.white.withAlphaComponent(0.19))
            for (i,row) in [("Ответить","arrowshape.turn.up.left"),("Копировать","document.on.document"),("Переслать","arrowshape.turn.up.right"),("Удалить","trash")].enumerated() {
                let y = CGFloat(i)*54; let c = i==3 ? color(0.78,0.25,0.38) : ink
                label(row.0,20,y,166,54,15,.medium,c,.left,menu.contentView); symbol(row.1,203,y+17,21,c,menu.contentView)
                if i<3 { line(20,y+54,204,menu.contentView) }
            }
            let compose = glass(21,784,300,54,27); symbol("plus",17,16,22,secondary,compose.contentView); label("Сообщение",54,0,200,54,15,.regular,secondary,.left,compose.contentView); symbol("face.smiling",262,15,24,secondary,compose.contentView)
            let mic = glass(333,784,49,54,25); symbol("mic.fill",14,16,21,accent,mic.contentView)
        }
    }
}

extension UILabel {
    func setLetterSpacing(_ value:CGFloat) { guard let text else{return}; attributedText = NSAttributedString(string:text,attributes:[.kern:value,.font:font as Any,.foregroundColor:textColor as Any]) }
}

@main @MainActor final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application:UIApplication,configurationForConnecting session:UISceneSession,options:UIScene.ConnectionOptions)->UISceneConfiguration {
        let config = UISceneConfiguration(name:"Audit",sessionRole:session.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

@MainActor final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene:UIScene,willConnectTo session:UISceneSession,options connectionOptions:UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let args = ProcessInfo.processInfo.arguments
        let mode = args.dropFirst().first ?? "components"
        let w = UIWindow(windowScene:scene); w.rootViewController = PreviewController(mode:mode); w.makeKeyAndVisible(); window=w
    }
}
