import Foundation

extension Episode {
  public static let ep260_observableArchitecture = Episode(
    blurb: """
      TODO
      """,
    codeSampleDirectory: "0260-observable-architecture-pt2",
    exercises: _exercises,
    id: 260,
    length: 43 * 60 + 3,
    permission: .subscriberOnly,
    publishedAt: yearMonthDayFormatter.date(from: "2023-12-04")!,
    references: [
      // TODO
    ],
    sequence: 260,
    subtitle: "TODO",
    title: "Observable Architecture",
    trailerVideo: .init(
      bytesLength: 42_100_000,
      downloadUrls: .s3(
        hd1080: "0260-trailer-1080p-8dc4311b606b4d6aae4575e2b93ee08e",
        hd720: "0260-trailer-720p-fd0dcc1c461643cf95696c62581fdccc",
        sd540: "0260-trailer-540p-b7f071ffcdd94303a57694f447ed171d"
      ),
      vimeoId: 887_464_399
    )
  )
}

private let _exercises: [Episode.Exercise] = [
  // TODO
]
