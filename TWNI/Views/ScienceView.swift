import SwiftUI

/// What TWNI is based on, what's known, and what it doesn't claim.
/// Keep every statement here backed by the linked sources.
struct ScienceView: View {
    private struct Source: Identifiable {
        let id = UUID()
        let title: String
        let url: String
    }

    private let sources: [Source] = [
        Source(
            title: "American Academy of Ophthalmology: tips for easing eye strain from screen time",
            url: "https://aao.org/newsroom/news-releases/detail/protect-your-eyes-in-home-office"
        ),
        Source(
            title: "Anbesu & Lema 2023, Scientific Reports: prevalence of computer vision syndrome (meta-analysis)",
            url: "https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9888747/"
        ),
        Source(
            title: "Ccami-Bernal et al. 2024, Journal of Optometry: prevalence of computer vision syndrome (meta-analysis)",
            url: "https://doi.org/10.1016/j.optom.2023.100482"
        ),
        Source(
            title: "Talens-Estarelles et al. 2023, Contact Lens & Anterior Eye: testing the 20-20-20 rule",
            url: "https://research.aston.ac.uk/en/publications/the-effects-of-breaks-on-digital-eye-strain-dry-eye-and-binocular/"
        ),
        Source(
            title: "Cochrane review 2023: blue-light filtering spectacle lenses",
            url: "https://www.cochranelibrary.com/cdsr/doi/10.1002/14651858.CD013244.pub2/full"
        ),
    ]

    var body: some View {
        Form {
            Section("The habit") {
                Text("Every 20 minutes of screen time, look at something about 6 m (20 ft) away for 20 seconds. Eye-care organizations such as the American Academy of Ophthalmology recommend it.")
            }
            Section("What research says") {
                Text("Eye strain from screens is common: in pooled studies, roughly 2 in 3 regular screen users report symptoms such as tired, dry or blurry eyes and headaches.")
                Text("Small studies suggest regular breaks ease these symptoms while you keep taking them. The evidence is still limited, and the 20-20-20 numbers are a rule of thumb.")
            }
            Section("Other habits that help") {
                Text("Keep screens about an arm's length away (45-65 cm, 18-25 in).")
                Text("Match screen brightness to the room and blink fully.")
                Text("Spend time outdoors. For children, it's linked with a lower risk of becoming short-sighted.")
            }
            Section("What TWNI doesn't do") {
                Text("TWNI doesn't measure, diagnose or treat your eyes. Blue-light glasses haven't been shown to reduce eye strain.")
                Text("If you have eye pain, sudden changes in vision or symptoms that don't go away, see an eye doctor.")
            }
            Section("Sources") {
                ForEach(sources) { source in
                    if let url = URL(string: source.url) {
                        Link(source.title, destination: url)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("The science")
    }
}
