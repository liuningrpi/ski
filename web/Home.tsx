/*
 * Design: "Alpine Noir" — Dark Cinematic Editorial
 * - Dark immersive canvas, frosted glass panels, electric cyan accent
 * - Instrument Serif headlines, DM Sans body, DM Mono stats
 * - Cinematic full-bleed imagery with overlaid typography
 */

import { useEffect, useRef, useState } from "react";
import { motion, useInView, useScroll, useTransform } from "framer-motion";
import {
  MapPin,
  Timer,
  Gauge,
  Mountain,
  Shield,
  Zap,
  Moon,
  Database,
  ArrowDown,
  Github,
  ChevronRight,
  Smartphone,
  Code2,
  Route,
} from "lucide-react";

// CDN URLs
const HERO_BG = "https://files.manuscdn.com/user_upload_by_module/session_file/310519663283865327/XGSiUIGkiMOHAxnO.jpg";
const HERO_MOCKUP = "https://files.manuscdn.com/user_upload_by_module/session_file/310519663283865327/yzzRJLSmzLGXSkOr.png";
const SCREEN_TRACKING = "https://files.manuscdn.com/user_upload_by_module/session_file/310519663283865327/imZyiXhQxiARVMmr.png";
const SCREEN_HISTORY = "https://files.manuscdn.com/user_upload_by_module/session_file/310519663283865327/zAxwgWvEWocSdvOG.png";
const SCREEN_START = "https://files.manuscdn.com/user_upload_by_module/session_file/310519663283865327/iEHtCzyEowGPHbKz.png";
const APP_ICON = "https://files.manuscdn.com/user_upload_by_module/session_file/310519663283865327/ZykMdrzxItnyaQzC.png";

// ─── Animated counter ────────────────────────────────────────
function AnimatedNumber({ value, suffix = "", decimals = 0 }: { value: number; suffix?: string; decimals?: number }) {
  const [display, setDisplay] = useState(0);
  const ref = useRef<HTMLSpanElement>(null);
  const inView = useInView(ref, { once: true, margin: "-100px" });

  useEffect(() => {
    if (!inView) return;
    const duration = 1200;
    const start = performance.now();
    const animate = (now: number) => {
      const elapsed = now - start;
      const progress = Math.min(elapsed / duration, 1);
      const eased = 1 - Math.pow(1 - progress, 3);
      setDisplay(eased * value);
      if (progress < 1) requestAnimationFrame(animate);
    };
    requestAnimationFrame(animate);
  }, [inView, value]);

  return (
    <span ref={ref} className="font-mono tabular-nums">
      {display.toFixed(decimals)}{suffix}
    </span>
  );
}

// ─── Section fade-in wrapper ─────────────────────────────────
function FadeIn({ children, className = "", delay = 0 }: { children: React.ReactNode; className?: string; delay?: number }) {
  const ref = useRef(null);
  const inView = useInView(ref, { once: true, margin: "-80px" });

  return (
    <motion.div
      ref={ref}
      initial={{ opacity: 0, y: 40 }}
      animate={inView ? { opacity: 1, y: 0 } : {}}
      transition={{ duration: 0.8, ease: [0.25, 0.46, 0.45, 0.94], delay }}
      className={className}
    >
      {children}
    </motion.div>
  );
}

// ─── Navigation ──────────────────────────────────────────────
function Nav() {
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 60);
    window.addEventListener("scroll", onScroll);
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <nav
      className={`fixed top-0 left-0 right-0 z-50 transition-all duration-500 ${
        scrolled ? "glass-panel py-3" : "py-5 bg-transparent"
      }`}
    >
      <div className="container flex items-center justify-between">
        <div className="flex items-center gap-3">
          <img src={APP_ICON} alt="Ski Tracker" className="w-9 h-9 rounded-xl" />
          <span className="font-serif text-xl text-snow tracking-wide">Ski Tracker</span>
        </div>
        <div className="hidden md:flex items-center gap-8 text-sm text-muted-foreground">
          <a href="#features" className="hover:text-foreground transition-colors duration-300">Features</a>
          <a href="#screens" className="hover:text-foreground transition-colors duration-300">Screenshots</a>
          <a href="#tech" className="hover:text-foreground transition-colors duration-300">Tech Stack</a>
          <a href="#setup" className="hover:text-foreground transition-colors duration-300">Setup</a>
        </div>
        <a
          href="https://github.com/liuningrpi/SkiTracker"
          target="_blank"
          rel="noopener noreferrer"
          className="flex items-center gap-2 px-4 py-2 rounded-lg glass-panel text-sm text-foreground hover:text-primary transition-colors duration-300"
        >
          <Github className="w-4 h-4" />
          <span className="hidden sm:inline">GitHub</span>
        </a>
      </div>
    </nav>
  );
}

// ─── Hero Section ────────────────────────────────────────────
function Hero() {
  const ref = useRef(null);
  const { scrollYProgress } = useScroll({
    target: ref,
    offset: ["start start", "end start"],
  });
  const bgY = useTransform(scrollYProgress, [0, 1], ["0%", "30%"]);
  const opacity = useTransform(scrollYProgress, [0, 0.8], [1, 0]);

  return (
    <section ref={ref} className="relative min-h-screen flex items-center overflow-hidden">
      {/* Parallax background */}
      <motion.div className="absolute inset-0 z-0" style={{ y: bgY }}>
        <img
          src={HERO_BG}
          alt=""
          className="w-full h-[130%] object-cover"
        />
        <div className="absolute inset-0 bg-gradient-to-b from-background/70 via-background/50 to-background" />
        <div className="absolute inset-0 bg-gradient-to-r from-background/80 via-transparent to-background/40" />
      </motion.div>

      <motion.div className="relative z-10 container pt-28 pb-20" style={{ opacity }}>
        <div className="grid lg:grid-cols-2 gap-12 lg:gap-8 items-center">
          {/* Left: Text */}
          <div className="max-w-xl">
            <motion.div
              initial={{ opacity: 0, y: 30 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.8, delay: 0.2 }}
            >
              <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-full glass-panel text-xs text-primary mb-6">
                <div className="w-1.5 h-1.5 rounded-full bg-primary animate-pulse" />
                Swift + SwiftUI · iOS 17+
              </div>
            </motion.div>

            <motion.h1
              initial={{ opacity: 0, y: 30 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.8, delay: 0.35 }}
              className="font-serif text-5xl sm:text-6xl lg:text-7xl leading-[1.05] tracking-tight mb-6"
            >
              Track Every
              <br />
              <span className="text-primary text-glow">Turn</span> Down
              <br />
              the Mountain
            </motion.h1>

            <motion.p
              initial={{ opacity: 0, y: 30 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.8, delay: 0.5 }}
              className="text-lg text-muted-foreground leading-relaxed mb-8 max-w-md"
            >
              A lightweight iOS app that records your skiing tracks with GPS precision.
              Real-time stats, beautiful map visualization, and local data storage — all running natively on your iPhone.
            </motion.p>

            <motion.div
              initial={{ opacity: 0, y: 30 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.8, delay: 0.65 }}
              className="flex flex-wrap gap-4"
            >
              <a
                href="https://github.com/liuningrpi/SkiTracker"
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center gap-2 px-6 py-3 rounded-xl bg-primary text-primary-foreground font-medium hover:opacity-90 transition-opacity"
              >
                <Github className="w-4 h-4" />
                View on GitHub
              </a>
              <a
                href="#features"
                className="inline-flex items-center gap-2 px-6 py-3 rounded-xl glass-panel text-foreground font-medium hover:bg-white/10 transition-colors"
              >
                Explore Features
                <ChevronRight className="w-4 h-4" />
              </a>
            </motion.div>
          </div>

          {/* Right: Phone mockup */}
          <motion.div
            initial={{ opacity: 0, y: 50, rotateY: -8 }}
            animate={{ opacity: 1, y: 0, rotateY: 0 }}
            transition={{ duration: 1, delay: 0.5, ease: [0.25, 0.46, 0.45, 0.94] }}
            className="flex justify-center lg:justify-end"
          >
            <div className="relative">
              <div className="absolute -inset-8 bg-primary/10 rounded-full blur-3xl" />
              <img
                src={HERO_MOCKUP}
                alt="Ski Tracker app showing GPS track on mountain map"
                className="relative w-[280px] sm:w-[320px] lg:w-[360px] drop-shadow-2xl"
              />
            </div>
          </motion.div>
        </div>

        {/* Scroll indicator */}
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 1.5 }}
          className="absolute bottom-8 left-1/2 -translate-x-1/2"
        >
          <motion.div
            animate={{ y: [0, 8, 0] }}
            transition={{ repeat: Infinity, duration: 2, ease: "easeInOut" }}
          >
            <ArrowDown className="w-5 h-5 text-muted-foreground" />
          </motion.div>
        </motion.div>
      </motion.div>
    </section>
  );
}

// ─── Stats Bar ───────────────────────────────────────────────
function StatsBar() {
  const stats = [
    { label: "GPS Accuracy", value: 20, suffix: "m", decimals: 0, description: "Max horizontal accuracy filter" },
    { label: "Speed Cap", value: 216, suffix: " km/h", decimals: 0, description: "Anomaly speed threshold" },
    { label: "Data Points", value: 100, suffix: "%", decimals: 0, description: "Local device storage" },
    { label: "Battery Smart", value: 3, suffix: "-10m", decimals: 0, description: "Dynamic distance filter" },
  ];

  return (
    <section className="relative py-16 border-y border-border/50">
      <div className="container">
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-8">
          {stats.map((stat, i) => (
            <FadeIn key={stat.label} delay={i * 0.1}>
              <div className="text-center">
                <div className="text-3xl sm:text-4xl font-serif text-primary text-glow mb-1">
                  <AnimatedNumber value={stat.value} suffix={stat.suffix} decimals={stat.decimals} />
                </div>
                <div className="text-sm font-medium text-foreground mb-1">{stat.label}</div>
                <div className="text-xs text-muted-foreground">{stat.description}</div>
              </div>
            </FadeIn>
          ))}
        </div>
      </div>
    </section>
  );
}

// ─── Features Section ────────────────────────────────────────
function Features() {
  const features = [
    {
      icon: <MapPin className="w-5 h-5" />,
      title: "Live GPS Tracking",
      description: "High-precision location recording with CoreLocation's best-for-navigation accuracy. Every turn, every run captured in real time.",
    },
    {
      icon: <Route className="w-5 h-5" />,
      title: "Map Visualization",
      description: "Beautiful polyline rendering on MapKit with auto-follow camera. Watch your track unfold as you carve down the mountain.",
    },
    {
      icon: <Gauge className="w-5 h-5" />,
      title: "Real-time Statistics",
      description: "Duration, distance, max speed, average speed, altitude, and elevation drop — all computed live with intelligent filtering.",
    },
    {
      icon: <Database className="w-5 h-5" />,
      title: "Local JSON Storage",
      description: "Sessions saved as clean, exportable JSON files. No cloud dependency, no account required. Your data stays on your device.",
    },
    {
      icon: <Moon className="w-5 h-5" />,
      title: "Background Recording",
      description: "Lock your screen and keep skiing. Background location updates ensure continuous tracking even when the app isn't visible.",
    },
    {
      icon: <Shield className="w-5 h-5" />,
      title: "Smart Data Filtering",
      description: "Multi-layer noise reduction: accuracy threshold (≤20m), teleport filter (≤100m/step), and speed anomaly rejection (≤60 m/s).",
    },
    {
      icon: <Zap className="w-5 h-5" />,
      title: "Adaptive Power Saving",
      description: "Dynamic distance filter adjusts from 3m at high speed to 10m when stationary, optimizing battery life without sacrificing track quality.",
    },
    {
      icon: <Timer className="w-5 h-5" />,
      title: "Session Replay",
      description: "Review your last session with full map replay and complete statistics. Relive every run from the comfort of the lodge.",
    },
  ];

  return (
    <section id="features" className="py-24 relative">
      <div className="container">
        <FadeIn>
          <div className="max-w-2xl mb-16">
            <p className="text-primary text-sm font-medium tracking-widest uppercase mb-3">Capabilities</p>
            <h2 className="font-serif text-4xl sm:text-5xl tracking-tight mb-4">
              Built for the Slopes
            </h2>
            <p className="text-muted-foreground text-lg leading-relaxed">
              Every feature designed with skiing in mind — from the precision of GPS filtering
              to the intelligence of adaptive power management.
            </p>
          </div>
        </FadeIn>

        <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-5">
          {features.map((feature, i) => (
            <FadeIn key={feature.title} delay={i * 0.08}>
              <div className="group glass-panel rounded-2xl p-6 h-full hover:border-primary/30 transition-all duration-500">
                <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center text-primary mb-4 group-hover:bg-primary/20 transition-colors duration-300">
                  {feature.icon}
                </div>
                <h3 className="font-medium text-foreground mb-2">{feature.title}</h3>
                <p className="text-sm text-muted-foreground leading-relaxed">{feature.description}</p>
              </div>
            </FadeIn>
          ))}
        </div>
      </div>
    </section>
  );
}

// ─── Screenshots Section ─────────────────────────────────────
function Screenshots() {
  const screens = [
    { src: SCREEN_START, label: "Ready to Ski", description: "One tap to start recording" },
    { src: SCREEN_TRACKING, label: "Live Tracking", description: "Real-time map and stats" },
    { src: SCREEN_HISTORY, label: "Session Review", description: "Full replay with details" },
  ];

  return (
    <section id="screens" className="py-24 relative overflow-hidden">
      {/* Subtle background gradient */}
      <div className="absolute inset-0 bg-gradient-to-b from-transparent via-primary/[0.03] to-transparent" />

      <div className="container relative">
        <FadeIn>
          <div className="text-center max-w-2xl mx-auto mb-16">
            <p className="text-primary text-sm font-medium tracking-widest uppercase mb-3">App Screens</p>
            <h2 className="font-serif text-4xl sm:text-5xl tracking-tight mb-4">
              Designed for Clarity
            </h2>
            <p className="text-muted-foreground text-lg leading-relaxed">
              Clean SwiftUI interface that puts your track front and center.
              Glanceable stats when you need them, out of the way when you don't.
            </p>
          </div>
        </FadeIn>

        <div className="flex flex-col md:flex-row items-center justify-center gap-8 md:gap-12">
          {screens.map((screen, i) => (
            <FadeIn key={screen.label} delay={i * 0.15}>
              <div className="flex flex-col items-center">
                <div className="relative group">
                  <div className="absolute -inset-4 bg-primary/5 rounded-[2rem] opacity-0 group-hover:opacity-100 transition-opacity duration-500 blur-xl" />
                  <img
                    src={screen.src}
                    alt={screen.label}
                    className="relative w-[220px] sm:w-[240px] rounded-[2rem] shadow-2xl shadow-black/40 border border-white/5 group-hover:scale-[1.02] transition-transform duration-500"
                  />
                </div>
                <div className="mt-6 text-center">
                  <p className="font-medium text-foreground">{screen.label}</p>
                  <p className="text-sm text-muted-foreground">{screen.description}</p>
                </div>
              </div>
            </FadeIn>
          ))}
        </div>
      </div>
    </section>
  );
}

// ─── Tech Stack Section ──────────────────────────────────────
function TechStack() {
  const stack = [
    { name: "Swift", detail: "5.9+", category: "Language" },
    { name: "SwiftUI", detail: "iOS 17", category: "UI Framework" },
    { name: "CoreLocation", detail: "Best for Nav", category: "GPS" },
    { name: "MapKit", detail: "MKPolyline", category: "Maps" },
    { name: "FileManager", detail: "JSON / Codable", category: "Storage" },
    { name: "Xcode", detail: "15+", category: "IDE" },
  ];

  return (
    <section id="tech" className="py-24 relative">
      <div className="container">
        <div className="grid lg:grid-cols-2 gap-16 items-start">
          <FadeIn>
            <div>
              <p className="text-primary text-sm font-medium tracking-widest uppercase mb-3">Architecture</p>
              <h2 className="font-serif text-4xl sm:text-5xl tracking-tight mb-6">
                Native & Lightweight
              </h2>
              <p className="text-muted-foreground text-lg leading-relaxed mb-8">
                Zero third-party dependencies. Built entirely with Apple's native frameworks
                for maximum performance and minimum footprint. The entire project compiles in seconds
                and runs on any iPhone with iOS 17.
              </p>

              <div className="glass-panel rounded-2xl p-6">
                <div className="flex items-center gap-3 mb-4">
                  <Code2 className="w-5 h-5 text-primary" />
                  <span className="text-sm font-medium">Project Structure</span>
                </div>
                <pre className="text-sm text-muted-foreground font-mono leading-relaxed overflow-x-auto">
{`SkiTracker/
├── App/
│   └── SkiTrackerApp.swift
├── Location/
│   └── LocationTracker.swift
├── Model/
│   └── TrackModels.swift
├── Storage/
│   └── SessionStore.swift
└── UI/
    ├── ContentView.swift
    ├── TrackMapView.swift
    ├── StatsView.swift
    └── HistoryView.swift`}
                </pre>
              </div>
            </div>
          </FadeIn>

          <FadeIn delay={0.2}>
            <div className="grid grid-cols-2 gap-4">
              {stack.map((item, i) => (
                <motion.div
                  key={item.name}
                  initial={{ opacity: 0, scale: 0.95 }}
                  whileInView={{ opacity: 1, scale: 1 }}
                  transition={{ delay: i * 0.08, duration: 0.5 }}
                  viewport={{ once: true }}
                  className="glass-panel rounded-xl p-5 hover:border-primary/20 transition-colors duration-300"
                >
                  <p className="text-xs text-primary font-medium tracking-wider uppercase mb-2">{item.category}</p>
                  <p className="text-lg font-medium text-foreground">{item.name}</p>
                  <p className="text-sm text-muted-foreground font-mono">{item.detail}</p>
                </motion.div>
              ))}
            </div>
          </FadeIn>
        </div>
      </div>
    </section>
  );
}

// ─── Data Filtering Section ──────────────────────────────────
function DataFiltering() {
  const filters = [
    { rule: "Horizontal Accuracy", threshold: "≤ 20m", description: "Reject low-quality GPS points" },
    { rule: "Single-step Distance", threshold: "≤ 100m", description: "Filter teleportation artifacts" },
    { rule: "Speed Upper Bound", threshold: "≤ 216 km/h", description: "Reject anomalous speed values" },
    { rule: "Invalid Speed", threshold: "speed < 0", description: "CLLocation returns -1 for invalid" },
  ];

  return (
    <section className="py-24 relative">
      <div className="absolute inset-0 bg-gradient-to-b from-transparent via-primary/[0.02] to-transparent" />
      <div className="container relative">
        <FadeIn>
          <div className="max-w-2xl mx-auto text-center mb-12">
            <p className="text-primary text-sm font-medium tracking-widest uppercase mb-3">Data Quality</p>
            <h2 className="font-serif text-4xl sm:text-5xl tracking-tight mb-4">
              Precision You Can Trust
            </h2>
            <p className="text-muted-foreground text-lg leading-relaxed">
              Multi-layer filtering ensures your track data is clean and accurate,
              even in challenging mountain conditions.
            </p>
          </div>
        </FadeIn>

        <FadeIn delay={0.15}>
          <div className="max-w-3xl mx-auto glass-panel rounded-2xl overflow-hidden">
            <div className="grid grid-cols-3 gap-px bg-border/30 text-xs font-medium text-muted-foreground uppercase tracking-wider">
              <div className="bg-card p-4">Filter Rule</div>
              <div className="bg-card p-4">Threshold</div>
              <div className="bg-card p-4">Purpose</div>
            </div>
            {filters.map((f, i) => (
              <div key={f.rule} className="grid grid-cols-3 gap-px bg-border/30">
                <div className="bg-card/80 p-4 text-sm font-medium text-foreground">{f.rule}</div>
                <div className="bg-card/80 p-4 text-sm font-mono text-primary">{f.threshold}</div>
                <div className="bg-card/80 p-4 text-sm text-muted-foreground">{f.description}</div>
              </div>
            ))}
          </div>
        </FadeIn>
      </div>
    </section>
  );
}

// ─── Setup Section ───────────────────────────────────────────
function Setup() {
  const steps = [
    { num: "01", title: "Clone the Repository", code: "gh repo clone liuningrpi/SkiTracker" },
    { num: "02", title: "Open in Xcode", code: "open SkiTracker.xcodeproj" },
    { num: "03", title: "Configure Signing", code: "Select your Team in Signing & Capabilities" },
    { num: "04", title: "Run on Device", code: "Connect iPhone → Select target → Cmd+R" },
  ];

  return (
    <section id="setup" className="py-24 relative">
      <div className="container">
        <FadeIn>
          <div className="max-w-2xl mb-16">
            <p className="text-primary text-sm font-medium tracking-widest uppercase mb-3">Get Started</p>
            <h2 className="font-serif text-4xl sm:text-5xl tracking-tight mb-4">
              On Your iPhone in Minutes
            </h2>
            <p className="text-muted-foreground text-lg leading-relaxed">
              No App Store required. No paid developer account needed.
              Just Xcode, a USB cable, and your iPhone.
            </p>
          </div>
        </FadeIn>

        <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-6">
          {steps.map((step, i) => (
            <FadeIn key={step.num} delay={i * 0.1}>
              <div className="glass-panel rounded-2xl p-6 h-full relative overflow-hidden group">
                <span className="absolute -top-4 -right-2 text-[5rem] font-serif text-primary/[0.06] leading-none select-none group-hover:text-primary/[0.12] transition-colors duration-500">
                  {step.num}
                </span>
                <div className="relative">
                  <div className="text-primary font-mono text-sm mb-3">{step.num}</div>
                  <h3 className="font-medium text-foreground mb-3">{step.title}</h3>
                  <code className="text-xs text-muted-foreground font-mono bg-black/20 px-2 py-1 rounded block overflow-x-auto">
                    {step.code}
                  </code>
                </div>
              </div>
            </FadeIn>
          ))}
        </div>
      </div>
    </section>
  );
}

// ─── CTA Section ─────────────────────────────────────────────
function CTA() {
  return (
    <section className="py-24 relative overflow-hidden">
      <div className="absolute inset-0">
        <img src={HERO_BG} alt="" className="w-full h-full object-cover opacity-20" />
        <div className="absolute inset-0 bg-gradient-to-t from-background via-background/90 to-background/70" />
      </div>

      <div className="container relative">
        <FadeIn>
          <div className="max-w-2xl mx-auto text-center">
            <div className="inline-flex items-center gap-2 mb-6">
              <Smartphone className="w-5 h-5 text-primary" />
              <Mountain className="w-5 h-5 text-primary" />
            </div>
            <h2 className="font-serif text-4xl sm:text-5xl tracking-tight mb-6">
              Ready for Your Next
              <br />
              <span className="text-primary text-glow">Powder Day</span>?
            </h2>
            <p className="text-muted-foreground text-lg leading-relaxed mb-8 max-w-lg mx-auto">
              Open source, privacy-first, and built with care.
              Clone the repo, build it in Xcode, and hit the slopes.
            </p>
            <div className="flex flex-wrap justify-center gap-4">
              <a
                href="https://github.com/liuningrpi/SkiTracker"
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center gap-2 px-8 py-4 rounded-xl bg-primary text-primary-foreground font-medium text-lg hover:opacity-90 transition-opacity"
              >
                <Github className="w-5 h-5" />
                Get the Source Code
              </a>
            </div>
            <p className="text-xs text-muted-foreground mt-6">
              MIT License · Free Apple ID signing · Works on iPhone with iOS 17+
            </p>
          </div>
        </FadeIn>
      </div>
    </section>
  );
}

// ─── Footer ──────────────────────────────────────────────────
function Footer() {
  return (
    <footer className="py-8 border-t border-border/50">
      <div className="container">
        <div className="flex flex-col sm:flex-row items-center justify-between gap-4">
          <div className="flex items-center gap-3">
            <img src={APP_ICON} alt="" className="w-6 h-6 rounded-lg" />
            <span className="text-sm text-muted-foreground">
              Ski Tracker · Built with Swift + SwiftUI
            </span>
          </div>
          <div className="flex items-center gap-6 text-sm text-muted-foreground">
            <a
              href="https://github.com/liuningrpi/SkiTracker"
              target="_blank"
              rel="noopener noreferrer"
              className="hover:text-foreground transition-colors"
            >
              GitHub
            </a>
            <span>MIT License</span>
          </div>
        </div>
      </div>
    </footer>
  );
}

// ─── Main Page ───────────────────────────────────────────────
export default function Home() {
  return (
    <div className="min-h-screen bg-background text-foreground overflow-x-hidden">
      <Nav />
      <Hero />
      <StatsBar />
      <Features />
      <div className="gradient-line mx-auto max-w-4xl" />
      <Screenshots />
      <div className="gradient-line mx-auto max-w-4xl" />
      <TechStack />
      <DataFiltering />
      <Setup />
      <CTA />
      <Footer />
    </div>
  );
}
