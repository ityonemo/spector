%{
  configs: [
    %{
      name: "default",
      checks: %{
        disabled: [
          {Credo.Check.Refactor.Nesting, []}
        ]
      }
    }
  ]
}
