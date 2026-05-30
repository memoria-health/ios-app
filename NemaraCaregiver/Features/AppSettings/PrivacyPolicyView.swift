import SwiftUI

/// Modal sheet that renders the Nemara privacy notice. Source of truth
/// is dashboard.nemara-health.com/privacy; the text below is bundled
/// with the app so the screen renders offline and version-locks with
/// the release. Re-export from the dashboard and update the constants
/// here when the policy changes.
struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    ForEach(Self.sections.indices, id: \.self) { i in
                        section(Self.sections[i])
                    }
                    footer
                }
                .padding(20)
            }
            .background(NemaraColor.paper)
            .navigationTitle("Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(NemaraColor.ink2)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Privacy Notice")
                .font(NemaraFont.largeTitle)
                .foregroundStyle(NemaraColor.ink)
                .kerning(-1)
            Text("EFFECTIVE MAY 26, 2026  ·  LAST REVISED MAY 26, 2026")
                .font(NemaraFont.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(NemaraColor.ink3)
        }
    }

    @ViewBuilder
    private func section(_ s: PrivacySection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(s.title)
                .font(NemaraFont.title2)
                .foregroundStyle(NemaraColor.ink)
                .kerning(-0.3)
            ForEach(s.body.indices, id: \.self) { j in
                content(s.body[j])
            }
        }
    }

    @ViewBuilder
    private func content(_ c: PrivacyContent) -> some View {
        switch c {
        case .paragraph(let text):
            Text(Self.attributed(text))
                .font(NemaraFont.bodyLarge)
                .foregroundStyle(NemaraColor.ink2)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .subheading(let title):
            Text(title)
                .font(NemaraFont.bodySemibold)
                .foregroundStyle(NemaraColor.ink)
                .padding(.top, 4)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items.indices, id: \.self) { k in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("•")
                            .font(NemaraFont.bodyLarge.weight(.semibold))
                            .foregroundStyle(NemaraColor.terra)
                        Text(Self.attributed(items[k]))
                            .font(NemaraFont.bodyLarge)
                            .foregroundStyle(NemaraColor.ink2)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Direct privacy questions to:")
                .font(NemaraFont.bodySmall)
                .foregroundStyle(NemaraColor.ink3)
            Text("Sunny Cui")
                .font(NemaraFont.bodySemibold)
                .foregroundStyle(NemaraColor.ink)
            Text("sunnycui@stanford.edu  ·  716-602-1101")
                .font(NemaraFont.bodyMedium)
                .foregroundStyle(NemaraColor.ink2)
        }
        .padding(.top, 8)
    }

    private static func attributed(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s)) ?? AttributedString(s)
    }
}

private enum PrivacyContent {
    case paragraph(String)
    case subheading(String)
    case bullets([String])
}

private struct PrivacySection {
    let title: String
    let body: [PrivacyContent]
}

private extension PrivacyPolicyView {
    static let sections: [PrivacySection] = [
        PrivacySection(title: "Summary", body: [
            .paragraph("Nemara operates a household-activity monitoring service using a Sensor that streams live video and audio for real-time AI analysis and user access. Critically, Nemara does not maintain a stored library of video or audio for later replay. The system processes streams in real time and discards them. Event clips are briefly retained then automatically deleted. The service retains text descriptions of household activity, account data, and authentication metadata, but does not sell personal information, use it for advertising, or allow the AI provider to train on it."),
        ]),
        PrivacySection(title: "1. Introduction and Scope", body: [
            .paragraph("This Privacy Notice describes how Darda and Cui, Inc., operating as Nemara, collects, uses, and processes personal information in connection with the Service. The notice applies to all individuals accessing the Service, including account holders, authorized users, and monitored persons whose audio or visual likeness may be captured."),
        ]),
        PrivacySection(title: "2. Defined Terms", body: [
            .bullets([
                "**Account Holder.** The natural person creating a Nemara account and subscribing to the Service.",
                "**Authorized User.** Any individual granted access by the Account Holder.",
                "**Activity Record.** Time-stamped textual descriptions of household activity generated by the AI Provider.",
                "**AI Provider.** Third-party artificial-intelligence service processing Sensor streams in real time.",
                "**Dashboard.** Web-based application for accessing the Service.",
                "**Monitored Person.** Natural person whose likeness, voice, or personal attributes may be captured by a Sensor.",
                "**Personal Information.** Information identifying, relating to, or linked with a particular individual or household.",
                "**Sensor.** Apple iPhone running NemaraCam application paired to an Account Holder.",
                "**Service.** Collective term for Nemara's iOS caregiver app, NemaraCam app, Dashboard, Sensor, and related infrastructure.",
            ]),
        ]),
        PrivacySection(title: "3. Categories of Personal Information We Collect", body: [
            .subheading("3.1. Account and Profile Information"),
            .bullets([
                "Email address (unique account identifier).",
                "Display name selected by Account Holder.",
                "Telephone number (optional).",
                "Password, stored exclusively in salted and hashed form.",
            ]),
            .subheading("3.2. Configuration and Activity Records"),
            .bullets([
                "Monitored Persons, Sensors, and rooms configured by Account Holder.",
                "Enabled detectors and user-defined parameters.",
                "Activity Records with event type, occurrence time, and brief narrative.",
                "Authorized User reviews and notes.",
                "Aggregated patterns derived from Activity Records.",
            ]),
            .subheading("3.3. Device and Technical Information"),
            .bullets([
                "Apple Push Notification device tokens.",
                "iOS version and device model.",
                "Session-level authentication tokens.",
                "IP addresses and timestamps in server access logs.",
            ]),
            .subheading("3.4. Sensor Streams, Real-Time Only"),
            .paragraph("Active Sensors capture live video and audio streamed in real time but not stored for replay. Sensors may be paused or disconnected at any time. No video or audio leaves the room in either state."),
        ]),
        PrivacySection(title: "4. How We Use Personal Information", body: [
            .paragraph("Personal Information is processed for these legitimate purposes:"),
            .bullets([
                "Operating, maintaining, and providing Service features and functionality.",
                "Authenticating Authorized Users and maintaining account security.",
                "Delivering operational notifications including event alerts and account communications.",
                "Diagnosing technical problems, preventing abuse, and improving Service reliability.",
                "Complying with applicable laws and court orders.",
                "Establishing, exercising, or defending legal claims.",
            ]),
            .paragraph("The Service does not process personal information for advertising, does not sell it to third parties, and does not engage in cross-context behavioral advertising."),
        ]),
        PrivacySection(title: "5. How We Handle Sensor Video and Audio", body: [
            .paragraph("Active Sensor streams are transmitted in real time to the AI Provider for analysis and to Authorized Users viewing live sessions. Once processed, video and audio are discarded. Event clips flagged by the AI Provider are briefly retained for analysis then automatically deleted. Nemara does not maintain a library of stored video, audio, or media content accessible for later replay. Live look-in sessions are not recorded."),
        ]),
        PrivacySection(title: "6. Disclosure to Service Providers", body: [
            .paragraph("The Service operates through contractually bound Service Providers processing personal information solely for Service delivery and industry-standard security:"),
            .bullets([
                "**LiveKit Cloud.** Operates real-time relay for Sensor streams. Does not retain content.",
                "**Google LLC (Gemini API).** Primary AI Provider processing streams under enterprise terms prohibiting data retention and model training.",
                "**OpenAI, L.L.C.** Secondary AI Provider fallback with identical restrictions.",
                "**Supabase, Inc.** Provides database, authentication, messaging, and storage. US-hosted on AWS.",
                "**Railway Corporation.** Hosts Nemara backend.",
                "**Vercel Inc.** Hosts Dashboard.",
                "**Apple Inc.** Operates Apple Push Notification service.",
            ]),
            .paragraph("Beyond these providers, Nemara may disclose personal information to successor entities in mergers or acquisitions, in response to lawful governmental requests or legal process where disclosure appears required, or to enforce terms or protect rights and safety."),
        ]),
        PrivacySection(title: "7. Data Retention", body: [
            .paragraph("Personal Information is retained only as reasonably necessary:"),
            .bullets([
                "**Live Sensor streams.** Held in memory only for the seconds needed for real-time analysis, not persisted.",
                "**Event clips.** Briefly retained for processing then automatically deleted.",
                "**Activity Records, configuration, account, profile information, and aggregated patterns.** Retained during active account status.",
                "**Server access logs.** Retained up to ninety (90) days for security and abuse prevention.",
                "**Account closure.** Personal Information deleted within thirty (30) days, except where required by law or for legal claims.",
            ]),
        ]),
        PrivacySection(title: "8. International Data Transfers", body: [
            .paragraph("Personal Information is processed and stored primarily in the United States. Users accessing the Service from outside the US consent to transfer and processing in the US, which may have different data-protection rules. Nemara implements appropriate safeguards where required by law."),
        ]),
        PrivacySection(title: "9. Live Look-In and Access Controls", body: [
            .paragraph("Authorized Users may view live Sensor streams through the application or Dashboard. Look-in sessions are transmitted in real time, require authentication, and are not recorded by Nemara. Access is limited to the Account Holder and Authorized Users granted access by the Account Holder. Nemara personnel and AI Provider personnel cannot view streams."),
        ]),
        PrivacySection(title: "10. Information Security", body: [
            .paragraph("Nemara employs administrative, technical, and physical safeguards protecting personal information against unauthorized access, alteration, disclosure, or destruction:"),
            .bullets([
                "Transport-layer encryption (TLS) for all data in transit.",
                "Encryption at rest for stored personal information.",
                "Row-level security policies scoped to authenticated principals.",
                "Secure authentication token storage in iOS Keychain.",
                "Logical and physical access controls over Service Provider infrastructure.",
            ]),
            .paragraph("No system can be guaranteed entirely secure. In the event of a security incident creating material risk of significant harm, Nemara will provide notice per applicable breach-notification laws."),
        ]),
        PrivacySection(title: "11. Your Rights", body: [
            .subheading("11.1. General Rights"),
            .paragraph("Subject to applicable law and identity verification, you have rights to:"),
            .bullets([
                "Request access to personal information held about you.",
                "Request correction of inaccurate or incomplete personal information.",
                "Request deletion of personal information.",
                "Withdraw consent and deactivate associated Sensors.",
                "Request a portable copy of your personal information.",
            ]),
            .paragraph("Exercise these rights by contacting Nemara at the address in Section 18. Verified requests receive responses within thirty (30) days or longer as permitted by law."),
            .subheading("11.2. California Privacy Rights (CCPA/CPRA)"),
            .paragraph("California residents have additional rights including knowing categories and specific pieces of personal information collected in the preceding twelve (12) months, requesting deletion, correcting inaccurate information, opting out of sale or sharing, and limiting use of sensitive personal information."),
            .paragraph("Nemara does not sell or share personal information as defined under CCPA, and does not use or disclose sensitive personal information outside permitted purposes without offering opportunity to limit use. Contact the address in Section 18 to exercise California privacy rights. You may designate an authorized agent subject to identity verification."),
            .subheading("11.3. European Privacy Rights (GDPR)"),
            .paragraph("Residents of the European Economic Area, United Kingdom, or Switzerland may have additional rights under GDPR or analogous law, including access, rectification, erasure, restriction of processing, data portability, and objection. You may lodge a complaint with a supervisory authority. Lawful bases for processing include contract performance, legitimate interests, consent where required, and legal obligation compliance."),
            .subheading("11.4. Canadian Privacy Rights (PIPEDA)"),
            .paragraph("Canadian residents have rights under the Personal Information Protection and Electronic Documents Act and analogous provincial legislation, including access, correction, and consent withdrawal. You may lodge a complaint with the privacy contact or the Office of the Privacy Commissioner of Canada."),
        ]),
        PrivacySection(title: "12. Children's Privacy", body: [
            .paragraph("The Service is not directed to children under thirteen (13) and Nemara does not knowingly collect personal information from anyone under thirteen (13). Upon learning of collection from a child under thirteen (13), that information will be promptly deleted. Report suspected collection via the contact information in Section 18."),
        ]),
        PrivacySection(title: "13. Consent of Monitored Persons", body: [
            .paragraph("The Account Holder must obtain and document consent from each Monitored Person prior to installing or activating a Sensor, and inform visitors and third parties in the monitored space that Sensors are in use. Do not install a Sensor where any present person has not agreed to monitoring. Recording individuals without consent may violate applicable jurisdiction laws. The Account Holder bears sole responsibility for compliance."),
        ]),
        PrivacySection(title: "14. Limitations on Use", body: [
            .paragraph("Nemara will not:"),
            .bullets([
                "Maintain a video or audio archive accessible for later replay.",
                "Sell, rent, or trade personal information to third parties.",
                "Use personal information for advertising, marketing, or commercial profiling.",
                "Disclose personal information to insurance companies, employers, or government agencies except as required by law.",
                "Permit the AI Provider or other Service Providers to retain personal information beyond necessary periods or use it to train artificial-intelligence models.",
            ]),
        ]),
        PrivacySection(title: "15. Cookies and Similar Technologies", body: [
            .paragraph("The Dashboard uses strictly necessary cookies and session-management technologies for user authentication and session state maintenance. Nemara does not use third-party advertising cookies, tracking pixels, or behavioral-advertising trackers. Browser Do Not Track signals are honored to the extent technically feasible."),
        ]),
        PrivacySection(title: "16. Wellness Service, Not a Medical Device", body: [
            .paragraph("The Service is a general wellness service providing household-activity insights for informational and convenience purposes only. **The Service is not a medical device** and is not intended to diagnose, treat, cure, prevent, or monitor any disease, medical condition, or symptom. The Service is not a substitute for professional medical care, supervision, or emergency response."),
        ]),
        PrivacySection(title: "17. Changes to this Notice", body: [
            .paragraph("Nemara may amend this Notice periodically. Material changes trigger notification to active users via the Service or email. The Last Revised date indicates the most recent update. Continued Service use following notice constitutes acceptance of amendments."),
        ]),
        PrivacySection(title: "18. Contact", body: [
            .paragraph("Direct privacy questions, rights requests, or complaints to the contact below. Nemara endeavors to respond to verified requests within thirty (30) days."),
        ]),
    ]
}

#if DEBUG
#Preview {
    PrivacyPolicyView()
}
#endif
