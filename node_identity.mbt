///|
/// Compare node identity within a tree, independent of location views. Copies of
/// a tree and incremental parse results have distinct identities even when they
/// share syntax data. Editing a retained handle does not change its identity.
pub impl Eq for Node with fn equal(self, other) {
  guard self.id() == other.id() else { return false }
  match (self.owner, other.owner) {
    (Some(left), Some(right)) => physical_equal(left, right)
    (None, None) => physical_equal(self.data, other.data)
    _ => false
  }
}

///|
pub extend Node with Eq::{equal, not_equal}
