import Foundation
import Postbox

/// MetaGram profile details: a peer's data center and a user's approximate registration date.
public enum MetaGramPeerInfo {
    /// The data center that stores the peer's profile photo, which is the peer's own DC (as AyuGram reads it).
    /// Nil without a profile photo.
    public static func datacenterId(peer: EnginePeer) -> Int? {
        for representation in peer.profileImageRepresentations {
            if let resource = representation.resource as? CloudPeerPhotoSizeMediaResource {
                return resource.datacenterId
            }
        }
        return nil
    }

    public static func datacenterName(_ id: Int) -> String {
        switch id {
        case 1, 3:
            return "DC\(id), Miami FL, USA"
        case 2, 4:
            return "DC\(id), Amsterdam, NL"
        case 5:
            return "DC\(id), Singapore, SG"
        default:
            return "DC\(id)"
        }
    }

    /// Known account ids and when they were registered (unix time), in increasing order of both. User ids grow over
    /// time, so a registration date is estimated between the two nearest known points; it is approximate, a few
    /// months at worst. Computed on the device: the id is sent nowhere.
    private static let registrationPoints: [(id: Int64, date: Int32)] = [
        (2768409, 1383264000),
        (7679610, 1388448000),
        (11538514, 1391212800),
        (15835244, 1392940800),
        (23646077, 1393459200),
        (38015510, 1393632000),
        (44634663, 1399334400),
        (54845238, 1411257600),
        (63263518, 1414454400),
        (101260938, 1425600000),
        (111220210, 1429574400),
        (116812045, 1437696000),
        (130029930, 1441324800),
        (157242073, 1446768000),
        (171295414, 1457481600),
        (181783990, 1460246400),
        (222021233, 1465344000),
        (278941742, 1473465600),
        (294851037, 1479600000),
        (337808429, 1487635200),
        (369669043, 1490918400),
        (400169472, 1501459200),
        (616816630, 1529625600),
        (727572658, 1543708800),
        (925078064, 1563235200),
        (1054883348, 1585612800),
        (1227964864, 1596067200),
        (1382531194, 1600128000),
        (1658586909, 1613088000),
        (1719536397, 1619222400),
        (1807942741, 1625443200),
        (1972424006, 1631664000),
        (2138472342, 1637539200),
        (5336336790, 1646352000),
        (5522237606, 1654128000),
        (5707112959, 1663718400),
        (5885964106, 1671062400),
        (6020888206, 1675468800),
        (6108011341, 1680998400),
        (6279839148, 1688342400),
        (6429580803, 1692057600),
        (6813121418, 1698451200),
        (6925870357, 1701129600),
        (7026360622, 1707091200),
    ]

    public enum RegistrationDate {
        /// Registered before the first known point.
        case before(Int32)
        case approximately(Int32)
    }

    /// The approximate registration date of the user with this id (`PeerId.Id` value).
    public static func estimatedRegistrationDate(userId: Int64) -> RegistrationDate {
        let points = self.registrationPoints
        guard let first = points.first, let last = points.last else {
            return .approximately(0)
        }
        if userId < first.id {
            return .before(first.date)
        }
        let now = Int32(Date().timeIntervalSince1970)
        if userId >= last.id {
            // newer than the table: continue the last stretch's pace, never past today
            let previous = points[points.count - 2]
            let pace = Double(last.date - previous.date) / Double(last.id - previous.id)
            let date = Double(last.date) + Double(userId - last.id) * pace
            return .approximately(min(now, Int32(clamping: Int64(date))))
        }
        for i in 1 ..< points.count {
            let upper = points[i]
            if userId < upper.id {
                let lower = points[i - 1]
                let fraction = Double(userId - lower.id) / Double(upper.id - lower.id)
                let date = Double(lower.date) + fraction * Double(upper.date - lower.date)
                return .approximately(Int32(clamping: Int64(date)))
            }
        }
        return .approximately(last.date)
    }
}
