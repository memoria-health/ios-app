import SwiftUI

/// Modal sheet that renders the Memoria privacy notice. Bundled rather than
/// fetched so the screen works offline and version-locks with the release.
///
/// `sections` below is GENERATED — do not hand-edit it. The notice is written
/// once in nemara-backend/docs/legal/privacy-notice.md and rendered into here,
/// both consent-gate PDFs, and the web /privacy page. Hand-editing one surface
/// is how they drifted apart before 2026-08-23. To change the notice, edit the
/// markdown and re-run docs/legal/render_privacy.py.
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
            Text("EFFECTIVE AUGUST 23, 2026")
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
            Text("Memoria Privacy Team")
                .font(NemaraFont.bodySemibold)
                .foregroundStyle(NemaraColor.ink)
            Text("contact@memoria-health.com")
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
            .paragraph("Memoria is a care-monitoring service. Sensors stream live video and audio for real-time analysis so that authorized caregivers can be alerted to possible safety and routine events, and so they can look in on the home. What is retained, and for how long, is set out in Section 17. Memoria does not sell personal information, does not use it for advertising, and does not permit its AI providers to train their models on your data. Memoria may train its own models on identifiable data only if you opt in."),
        ]),
        PrivacySection(title: "1. Introduction and Scope", body: [
            .paragraph("This Notice describes how Darda and Cui, Inc., operating as Memoria, collects, uses, and processes personal information in connection with the Service. It applies to everyone whose information the Service touches, including account holders, authorized users, and monitored persons whose likeness or voice may be captured."),
            .paragraph("Memoria provides a care monitoring service that uses cameras, microphones, cloud-based analysis, alerting, and reporting to help legally authorized caregivers identify possible safety and routine-related events, including falls, choking, unusual inactivity, wandering, and other activities selected by the authorized caregiver."),
            .paragraph("The Service supports health and safety awareness and caregiver coordination. Under Section 7 of the DPDP Act, processing for medical emergencies and safety is a legitimate secondary line of defense, but imposes no proactive obligation on Memoria to act as an emergency response service. Unless stated otherwise in a separate written agreement, the Service is not a substitute for emergency response, professional medical care, diagnosis, treatment, or in-person supervision."),
        ]),
        PrivacySection(title: "2. Defined Terms", body: [
            .bullets([
                "**Account Holder.** The natural person creating a Memoria account and subscribing to the Service.",
                "**Authorized User.** Any individual granted access by the Account Holder.",
                "**Activity Record.** Time-stamped textual descriptions of household activity generated by the AI Provider.",
                "**AI Provider.** Third-party artificial-intelligence service processing Sensor streams in real time.",
                "**Dashboard.** Web-based application for accessing the Service.",
                "**Data Principal.** The monitored individual, as that term is used under the DPDP Act.",
                "**Monitored Person.** Natural person whose likeness, voice, or personal attributes may be captured by a Sensor.",
                "**Personal Information.** Information identifying, relating to, or linked with a particular individual or household.",
                "**Sensor.** A device running Memoria camera software and paired to an Account Holder.",
                "**Service.** Memoria's caregiver app, camera app, Dashboard, Sensors, and related infrastructure.",
            ]),
        ]),
        PrivacySection(title: "3. People Covered by This Notice", body: [
            .paragraph("This Notice applies to the monitored areas of a residence or care facility; the monitored individual (Data Principal); the caregiver or clinician; other residents, visitors, care workers, and anyone else who may enter monitored areas; and legal representatives who consent on behalf of another person."),
            .paragraph("Individuals below the legally consenting age in their locality may not sign up as an account administrator."),
        ]),
        PrivacySection(title: "4. Roles, Access, and Account Controls", body: [
            .paragraph("Roles should be assigned only to people with a legitimate care, safety, support, or legal need. Roles may include the monitored individual, a legal representative, the account administrator, a caregiver or clinician, and Memoria support personnel."),
            .paragraph("Support personnel review data strictly within a secure, closed environment on company-provided devices under confidentiality agreements."),
            .paragraph("The account administrator is responsible for ensuring each user has appropriate access. Unless settings state otherwise, authorized users may view sensitive information about the monitored person, including event clips, audio, activity history, health-related observations, and household information."),
            .paragraph("Memoria may provide audit logs, access history, role-based permissions, user removal, device disablement, clip deletion, download controls, and data and account erasure where available. The account administrator should promptly remove users who no longer need access."),
        ]),
        PrivacySection(title: "5. Consent to Audio and Video Recording", body: [
            .paragraph("By using the Service, you consent to the collection, recording, transmission, storage, analysis, and use of video, audio, images, activity signals, event clips, and related data as described in this Notice."),
            .paragraph("Under the DPDP framework, primary regulatory responsibility and liability as a Data Fiduciary remain with Memoria. While account administrators facilitate setup and local notices, legal consent must be obtained directly from Data Principals or their verified legal representatives."),
            .paragraph("If the monitored person cannot give legally valid consent, the person authorizing the Service represents that they have legal authority to do so, such as guardianship, power of attorney, or health care proxy authority."),
            .paragraph("The Service should not be used where people reasonably expect heightened privacy, such as bathrooms, changing areas, or bedrooms used by visitors, unless all legally required consents are obtained and the use is lawful."),
        ]),
        PrivacySection(title: "6. Notice to Visitors and Care Workers", body: [
            .paragraph("The account administrator must give reasonable notice to visitors and care workers that audio and video monitoring may occur, by posted signs, verbal or written notice, QR codes, or other methods required by law."),
            .paragraph("Sample notice language: \"Audio and video monitoring may be active in this area for care and safety purposes. By entering monitored areas, you may be recorded. For questions, contact [Name / Phone / Email].\""),
        ]),
        PrivacySection(title: "7. Categories of Personal Information We Collect", body: [
            .paragraph("**Account and profile information.** Email address, display name, telephone number (optional), and password stored exclusively in salted and hashed form. Account role, payment and billing status, and login activity."),
            .paragraph("**Configuration and activity records.** Monitored persons, Sensors, and rooms configured by the account holder; enabled detectors and their parameters; Activity Records with event type, time, and a brief narrative; authorized user reviews and notes; and aggregated patterns derived from Activity Records."),
            .paragraph("**Sensor streams.** Live video and audio from cameras in monitored areas."),
            .paragraph("**Biometrics.** Facial geometry and related characteristics used to distinguish individuals, as described in Section 14."),
            .paragraph("**Health-related observations** inferred from monitoring, such as a possible fall or possible choking event."),
            .paragraph("**Device and technical information.** Push notification tokens, OS version and device model, session authentication tokens, camera and network status, diagnostic logs, and IP addresses and timestamps in server access logs."),
            .paragraph("**Communications with us,** including support requests, feedback, and incident reports."),
            .paragraph("If the Service is used to monitor minors or individuals under guardianship, verifiable parental or legal guardian consent is required."),
        ]),
        PrivacySection(title: "8. How We Use Personal Information", body: [
            .paragraph("Personal information is processed to operate, maintain, and improve the Service; detect and surface possible safety and routine events; send alerts, summaries, clips, and insights to authorized users; configure custom activity monitoring; troubleshoot Sensors, alerts, and account access; maintain security and prevent fraud; comply with legal obligations and enforce our terms; establish, exercise, or defend legal claims; and develop and evaluate product features subject to the limits in this Notice."),
            .paragraph("Memoria does not process personal information for advertising, does not sell it, and does not engage in cross-context behavioral advertising."),
        ]),
        PrivacySection(title: "9. Consent Conflicts and Withdrawal", body: [
            .paragraph("The Service should be used only where all legally required consents have been obtained and remain valid. If the monitored individual withdraws consent, objects to monitoring, or asks that monitoring stop, the account administrator must promptly disable monitoring and notify Memoria to delete the raw data and account information relating to that individual."),
            .paragraph("Active monitoring ceases immediately on withdrawal of consent. Previously collected data is retained after withdrawal only where a specific and valid statutory or legal retention basis applies."),
            .paragraph("If disputes arise among family members, caregivers, or legal representatives about consent, access, or deletion, Memoria may request legal documentation such as a power of attorney or court order, restrict access, preserve data where legally required, or suspend monitoring until the dispute is resolved."),
        ]),
        PrivacySection(title: "10. How We Handle Sensor Video and Audio", body: [
            .paragraph("Active Sensor streams are transmitted in real time to the AI Provider for analysis and to authorized users viewing live sessions. Live look-in sessions are not recorded by Memoria. Retention of streams and event clips is governed by Section 17."),
        ]),
        PrivacySection(title: "11. AI, Automated Analysis, and Model Training", body: [
            .paragraph("The Service uses automated systems, including machine learning models, to analyze audio, video, and activity data. These systems may identify patterns consistent with safety and routine events, and may produce false positives, false negatives, delayed alerts, or incorrect classifications. Automated analysis may be affected by environment, lighting, placement, or network stability."),
            .paragraph("**Security in processing.** Video, audio, and event data are encrypted in transit and at rest. Analyzing this data requires the Service to process it in unencrypted form on Memoria's systems and those of the service providers listed in Section 15."),
            .paragraph("**Model training.** Memoria does not permit the AI Provider, or any other service provider, to use your data to train their models. Provider contracts prohibit it, and that prohibition is not something you can opt into waiving."),
            .paragraph("Memoria may train or fine-tune its own models on identifiable video, audio, and event data, and does so only with your explicit opt-in consent. Opt-in is off by default and can be withdrawn at any time."),
        ]),
        PrivacySection(title: "12. Human Review", body: [
            .paragraph("In limited circumstances, authorized Memoria personnel or contractors may review video, audio, event clips, or technical logs for troubleshooting, safety verification, or quality assurance."),
            .paragraph("Material under review is pseudonymized: it is identified by opaque record and device identifiers rather than by the monitored person's name or account details."),
            .paragraph("Review is limited to authorized personnel with a clear need to know, takes place within a secure closed environment on encrypted company-managed hardware, and is subject to confidentiality agreements, access logging, and data-isolation controls."),
        ]),
        PrivacySection(title: "13. Live Look-In and Access Controls", body: [
            .paragraph("Authorized users may view live Sensor streams through the application or Dashboard. Look-in sessions are transmitted in real time, require authentication, and are not recorded by Memoria. Access is limited to the account holder and the authorized users they grant access to."),
        ]),
        PrivacySection(title: "14. Biometric Data", body: [
            .paragraph("Some features process biometric information, such as facial geometry, to distinguish individuals and reduce false alerts. Biometric data is retained only as long as necessary to provide the enabled feature or as required by law. Where a jurisdiction requires specific written biometric consent, the feature remains disabled until valid consent is logged."),
        ]),
        PrivacySection(title: "15. Disclosure to Service Providers", body: [
            .paragraph("The Service operates through contractually bound service providers that process personal information solely for Service delivery:"),
            .bullets([
                "**LiveKit Cloud.** Real-time relay for Sensor streams. Does not retain content.",
                "**Google LLC (Gemini API).** Primary AI Provider, under enterprise terms prohibiting data retention and model training.",
                "**OpenAI, L.L.C.** Secondary AI Provider fallback with identical restrictions.",
                "**Supabase, Inc.** Database, authentication, messaging, and storage. US-hosted on AWS.",
                "**Railway Corporation.** Hosts the Memoria backend.",
                "**Vercel Inc.** Hosts the Dashboard.",
                "**Apple Inc.** Push notification delivery.",
            ]),
            .paragraph("Memoria may also disclose personal information to authorized family members and caregivers designated by the account administrator; to emergency contacts or responders where escalation features are enabled; to health care providers authorized by the monitored person or their legal representative; to successor entities in a merger, acquisition, or asset sale under non-disclosure protections; and to legal, regulatory, or safety authorities where required by law or under emergency provisions."),
            .paragraph("Memoria does not sell raw video or audio recordings."),
        ]),
        PrivacySection(title: "16. Downloads and Onward Sharing by Users", body: [
            .paragraph("Authorized users may view, download, screenshot, or forward alerts, clips, and summaries. Once information is exported outside the Service, that party acts independently in respect of it, and Memoria is not responsible for downstream misuse it did not initiate or direct."),
            .paragraph("Users must not use exported information for harassment, public posting, employment discrimination, insurance decisions, or unlawful purposes."),
        ]),
        PrivacySection(title: "17. Data Retention", body: [
            .paragraph("Personal information is retained only as long as necessary for the purposes in this Notice, unless a longer period is required by contract, legal dispute, or law."),
            .bullets([
                "**Continuous raw video and audio.** Up to 6 months, and only where the user has explicitly enabled it.",
                "**Event clips and alerts.** Retained for the life of the account.",
                "**Metadata, thumbnails, and AI logs.** 12 months.",
                "**Security logs.** 12 months.",
                "**System backups.** 2 weeks.",
                "**Account, profile, configuration, and Activity Records.** Retained while the account is active.",
                "**Account closure.** Personal information is deleted within thirty (30) days, except where retention is required by law or for legal claims.",
            ]),
        ]),
        PrivacySection(title: "18. International Data Transfers", body: [
            .paragraph("Personal information is processed and stored primarily in the United States. Users accessing the Service from outside the United States consent to transfer and processing there, which may have different data-protection rules. Memoria implements appropriate safeguards where required by law."),
            .paragraph("The Service is approved for operational use in the United States and India. Serving Indian users from a US-incorporated entity is permissible provided the DPDP framework is satisfied."),
        ]),
        PrivacySection(title: "19. Privacy, Intimate Recordings, and Quiet Hours", body: [
            .paragraph("Sensors are placed in private home or care environments. Users may schedule quiet hours or activate privacy mode to suspend recording, and may disable audio or individual cameras."),
            .paragraph("Memoria is not liable for accidental recordings that occur despite reasonable technical safeguards, including those caused by misconfigured settings or improper physical placement of devices."),
        ]),
        PrivacySection(title: "20. Information Security", body: [
            .paragraph("Memoria employs administrative, technical, and physical safeguards protecting personal information against unauthorized access, alteration, disclosure, or destruction:"),
            .bullets([
                "Transport-layer encryption (TLS) for all data in transit.",
                "Encryption at rest for stored personal information.",
                "Row-level security policies scoped to authenticated principals.",
                "Secure authentication token storage in the device keychain.",
                "Logical and physical access controls over service provider infrastructure.",
                "Access logging for personnel review.",
            ]),
            .paragraph("No system can be guaranteed entirely secure."),
        ]),
        PrivacySection(title: "21. Data Breach and Incident Notification", body: [
            .paragraph("If a security incident affecting personal data occurs, Memoria will investigate and notify impacted users and regulatory authorities without unreasonable delay as required by applicable law. Containment may include credential resets, device isolation, log preservation, and access restriction."),
            .paragraph("Report incidents or privacy concerns to contact@memoria-health.com."),
        ]),
        PrivacySection(title: "22. Your Rights and Choices", body: [
            .subheading("22.1 Controls in the Service"),
            .paragraph("Depending on configuration and local law, you may pause monitoring or enable privacy mode, disable audio or specific cameras, review and label event clips, request deletion of specific recording timeframes, and withdraw consent or close the account."),
            .subheading("22.2 General Rights"),
            .paragraph("Subject to applicable law and identity verification, you may request access to personal information held about you, correction of inaccurate or incomplete information, deletion, a portable copy, and withdrawal of consent with deactivation of the associated Sensors. You may also seek grievance redressal through Memoria or escalate to your regional regulator, such as the Data Protection Board."),
            .paragraph("To exercise these rights, email contact@memoria-health.com. Verified requests receive a response within thirty (30) days, or longer where permitted by law."),
            .subheading("22.3 California (CCPA/CPRA)"),
            .paragraph("California residents may know the categories and specific pieces of personal information collected in the preceding twelve (12) months, request deletion, correct inaccurate information, opt out of sale or sharing, and limit the use of sensitive personal information. Memoria does not sell or share personal information as defined under the CCPA. You may designate an authorized agent subject to identity verification."),
            .subheading("22.4 Europe and the United Kingdom (GDPR)"),
            .paragraph("Residents of the EEA, United Kingdom, or Switzerland may have rights of access, rectification, erasure, restriction of processing, data portability, and objection, and may lodge a complaint with a supervisory authority. Lawful bases include contract performance, legitimate interests, consent where required, and compliance with legal obligations."),
            .subheading("22.5 Canada (PIPEDA)"),
            .paragraph("Canadian residents have rights of access, correction, and consent withdrawal under PIPEDA and analogous provincial legislation, and may complain to the Office of the Privacy Commissioner of Canada."),
        ]),
        PrivacySection(title: "23. Facility, Shared Housing, and Resident Rights", body: [
            .paragraph("Where the Service is used in an assisted living facility, nursing home, group home, or shared housing, additional facility policies, lease terms, and resident rights apply."),
            .paragraph("The account administrator must obtain all necessary permissions from residents, roommates, facility management, and legal representatives before installation. Monitoring equipment must not be installed in shared private spaces without explicit, legally valid consent from all affected parties."),
        ]),
        PrivacySection(title: "24. Care Workers and Employees", body: [
            .paragraph("Where the Service monitors paid care workers, nurses, or agency employees, additional workplace privacy and labor notice requirements apply. Account administrators should review local employment regulations before monitoring workplace tasks."),
        ]),
        PrivacySection(title: "25. Law Enforcement, Legal Requests, and Emergencies", body: [
            .paragraph("Memoria has no duty to police or report general crimes, but may disclose information in response to valid court orders, subpoenas, or statutory obligations."),
            .paragraph("Memoria may disclose information without prior notice where reasonably necessary for a medical emergency, public safety, or preventing serious physical harm."),
        ]),
        PrivacySection(title: "26. Children's Privacy", body: [
            .paragraph("The Service is not directed to children under thirteen (13) and Memoria does not knowingly collect personal information from anyone under thirteen (13). On learning of such collection, that information is promptly deleted. Report suspected collection to contact@memoria-health.com."),
        ]),
        PrivacySection(title: "27. Cookies and Similar Technologies", body: [
            .paragraph("The Dashboard uses strictly necessary cookies and session-management technologies for authentication and session state. Memoria does not use third-party advertising cookies, tracking pixels, or behavioral-advertising trackers. Browser Do Not Track signals are honored where technically feasible."),
        ]),
        PrivacySection(title: "28. Wellness Service, Not a Medical Device", body: [
            .paragraph("The Service provides household-activity insights for informational purposes. **The Service is not a medical device** and is not intended to diagnose, treat, cure, prevent, or monitor any disease, condition, or symptom, and is not a substitute for professional medical care, supervision, or emergency response."),
            .paragraph("Safety alerts describe possible events, such as a possible fall or possible choking, and are not medical determinations. The Service does not guarantee detection of every emergency event. In an emergency, contact local emergency services directly."),
        ]),
        PrivacySection(title: "29. Limitations on Use", body: [
            .paragraph("Memoria will not:"),
            .bullets([
                "Sell, rent, or trade personal information to third parties.",
                "Use personal information for advertising, marketing, or commercial profiling.",
                "Disclose personal information to insurance companies, employers, or government agencies except as required by law.",
                "Permit the AI Provider, or any other service provider, to use personal information to train their models.",
                "Train Memoria's own models on identifiable video, audio, or event data without explicit opt-in consent.",
                "Permit service providers to retain personal information beyond the periods in Section 17.",
            ]),
        ]),
        PrivacySection(title: "30. Business and Facility Customers", body: [
            .paragraph("Where the Service is provided through senior living operators, healthcare agencies, or institutional facilities, contractual agreements such as Data Processing Agreements or Business Associate Agreements govern. Where such an executed agreement conflicts with this Notice, the executed agreement controls to the extent permitted by law."),
        ]),
        PrivacySection(title: "31. Changes to This Notice", body: [
            .paragraph("Memoria may amend this Notice periodically. Material changes trigger notification to active users through the Service or by email before they take effect. The Effective Date indicates the most recent update. Continued use of the Service after notice constitutes acceptance."),
        ]),
        PrivacySection(title: "32. Contact", body: [
            .paragraph("For privacy questions, rights requests, or complaints:"),
            .paragraph("Memoria Privacy Team 959 Stewart Drive, Apt 632 Sunnyvale, CA 94085, USA contact@memoria-health.com"),
            .paragraph("For security incidents: contact@memoria-health.com"),
        ]),
        PrivacySection(title: "33. Consent Acknowledgment", body: [
            .paragraph("By completing electronic acceptance, you acknowledge that:"),
            .bullets([
                "You have read and understand this Notice.",
                "You explicitly consent to the collection, processing, transmission, and storage of video, audio, and activity data as described.",
                "You confirm that you have legal capacity to consent, or are a co-signing family member or verified legal representative.",
                "Automated safety analysis may be delayed or limited by environmental conditions.",
                "The Service is not an emergency dispatch or medical treatment service.",
                "You agree to manage account access responsibly and to notify visitors and staff entering monitored areas.",
            ]),
            .paragraph("If you are setting up monitoring for another person, you confirm that you have the legal authority to consent on their behalf."),
        ]),
    ]
}

#if DEBUG
#Preview {
    PrivacyPolicyView()
}
#endif
