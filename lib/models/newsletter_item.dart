class NewsletterItem {
  final String id;
  final String source;
  final String date;
  final String title;
  final String body;
  final List<String> tags;
  final String readTime;

  const NewsletterItem({
    required this.id,
    required this.source,
    required this.date,
    required this.title,
    required this.body,
    required this.tags,
    required this.readTime,
  });
}

const List<NewsletterItem> sampleNewsletterItems = [
  NewsletterItem(
    id: '1',
    source: 'MIT Technology Review',
    date: 'Today',
    title: 'The Future of Generative AI in Scientific Research',
    body:
        'Researchers at leading universities are using large language models to accelerate discovery in fields from drug development to materials science.',
    tags: ['AI', 'Research', 'Science'],
    readTime: '4 min read',
  ),
  NewsletterItem(
    id: '2',
    source: 'Nature',
    date: 'Today',
    title: 'Breakthrough in Quantum Computing Stability',
    body:
        'A team of physicists has demonstrated sustained quantum coherence at room temperature, potentially transforming the path to practical quantum computers.',
    tags: ['Quantum', 'Computing', 'Physics'],
    readTime: '6 min read',
  ),
  NewsletterItem(
    id: '3',
    source: 'The Economist',
    date: 'Yesterday',
    title: 'Global Economic Outlook Amid AI Disruption',
    body:
        'New analysis shows automation is reshaping labor markets faster than predicted, with divergent effects across sectors and income levels.',
    tags: ['Economics', 'AI', 'Labor'],
    readTime: '5 min read',
  ),
  NewsletterItem(
    id: '4',
    source: 'Wired',
    date: 'Yesterday',
    title: 'Privacy in the Age of Personalized Algorithms',
    body:
        'As recommendation systems grow more powerful, experts debate whether stronger regulation or technical standards offer better consumer protection.',
    tags: ['Privacy', 'Technology', 'Policy'],
    readTime: '3 min read',
  ),
  NewsletterItem(
    id: '5',
    source: 'Harvard Business Review',
    date: '2 days ago',
    title: 'Knowledge Management for Distributed Teams',
    body:
        'Organizations that invest in structured knowledge repositories see measurable gains in onboarding speed and decision quality, new research finds.',
    tags: ['Management', 'Teams', 'Knowledge'],
    readTime: '7 min read',
  ),
  NewsletterItem(
    id: '6',
    source: 'ArXiv Digest',
    date: '2 days ago',
    title: 'Advances in Multimodal Foundation Models',
    body:
        'The latest generation of models can seamlessly reason across text, images, audio, and structured data, opening new research directions.',
    tags: ['ML', 'Research', 'Multimodal'],
    readTime: '8 min read',
  ),
];
