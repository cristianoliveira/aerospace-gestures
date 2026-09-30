/// Orders listener teardown and ignores duplicate termination signals while a child is stopping.
public final class ListenerShutdown {
  private let stopInput: () -> Void
  private let stopCommands: (@escaping () -> Void) -> Void
  private var isStopping = false
  private var didComplete = false
  private var completion: (() -> Void)?

  public init(
    stopInput: @escaping () -> Void,
    stopCommands: @escaping (@escaping () -> Void) -> Void
  ) {
    self.stopInput = stopInput
    self.stopCommands = stopCommands
  }

  public func stop(completion: @escaping () -> Void) {
    guard !isStopping else { return }
    isStopping = true
    self.completion = completion

    stopInput()
    stopCommands { [weak self] in
      guard let self, !self.didComplete else { return }
      self.didComplete = true
      let completion = self.completion
      self.completion = nil
      completion?()
    }
  }
}
