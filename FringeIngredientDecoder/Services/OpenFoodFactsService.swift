import Foundation

protocol ProductLookupServing {
    func lookup(barcode: String) async -> LookupOutcome
}

struct OpenFoodFactsService {
    func lookup(barcode: String) async -> LookupOutcome {
        let foodOutcome = await lookup(barcode: barcode, domain: .food)
        switch foodOutcome {
        case .found:
            return foodOutcome
        case .notFound:
            return await lookup(barcode: barcode, domain: .beauty)
        case .unavailable:
            let beautyOutcome = await lookup(barcode: barcode, domain: .beauty)
            if case .found = beautyOutcome {
                return beautyOutcome
            }
            return .unavailable
        }
    }

    func search(query: String, domain: ProductDomain, limit: Int = 12) async -> [RemoteProduct] {
        guard domain != .custom else { return [] }
        guard var components = URLComponents(string: "\(baseURL(for: domain))/cgi/search.pl") else {
            return []
        }

        components.queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: String(limit)),
            URLQueryItem(
                name: "fields",
                value: "code,product_name,product_name_en,generic_name,generic_name_en,brands,ingredients_text,ingredients_text_en,ingredients,image_front_small_url,image_front_url"
            )
        ]

        guard let url = components.url else { return [] }

        do {
            let root = try await performRequest(url: url)
            guard let products = root["products"] as? [[String: Any]] else { return [] }
            return products.compactMap { makeRemoteProduct(from: $0, fallbackBarcode: nil, domain: domain) }
        } catch {
            return []
        }
    }

    private func lookup(barcode: String, domain: ProductDomain) async -> LookupOutcome {
        guard let url = URL(string: "\(baseURL(for: domain))/api/v0/product/\(barcode).json") else {
            return .unavailable
        }

        do {
            let root = try await performRequest(url: url)
            guard let status = root["status"] as? Int else {
                return .unavailable
            }

            guard status == 1, let product = root["product"] as? [String: Any] else {
                return .notFound
            }

            guard let remote = makeRemoteProduct(from: product, fallbackBarcode: barcode, domain: domain) else {
                return .found(
                    RemoteProduct(
                        title: firstNonEmpty(
                            product["product_name"] as? String,
                            product["product_name_en"] as? String,
                            product["generic_name"] as? String,
                            product["brands"] as? String
                        ) ?? "Product",
                        ingredientsText: "",
                        barcode: barcode,
                        imageURL: firstNonEmpty(
                            product["image_front_small_url"] as? String,
                            product["image_front_url"] as? String
                        ),
                        domain: domain,
                        scoreInputs: scoreInputs(from: product, domain: domain)
                    )
                )
            }

            return .found(remote)
        } catch {
            return .unavailable
        }
    }

    private func performRequest(url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("FringeIngredientDecoder/1.1 (iOS)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200 ... 299).contains(response.statusCode) else {
            throw LookupError.unavailable
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LookupError.unavailable
        }

        return root
    }

    func makeRemoteProduct(from product: [String: Any], fallbackBarcode: String?, domain: ProductDomain) -> RemoteProduct? {
        let title = firstNonEmpty(
            product["product_name"] as? String,
            product["product_name_en"] as? String,
            product["generic_name"] as? String,
            product["generic_name_en"] as? String,
            product["brands"] as? String
        ) ?? "Product"

        let barcode = firstNonEmpty(product["code"] as? String, fallbackBarcode)
        let ingredientsText = firstNonEmpty(
            product["ingredients_text_en"] as? String,
            product["ingredients_text"] as? String,
            ingredientsString(from: product["ingredients"])
        )

        guard let barcode else { return nil }

        return RemoteProduct(
            title: title,
            ingredientsText: ingredientsText ?? "",
            barcode: barcode,
            imageURL: firstNonEmpty(
                product["image_front_small_url"] as? String,
                product["image_front_url"] as? String
            ),
            domain: domain,
            scoreInputs: scoreInputs(from: product, domain: domain)
        )
    }

    private func scoreInputs(from product: [String: Any], domain: ProductDomain) -> ProductScoreInputs? {
        guard domain == .food else { return nil }

        let nutritionGrade = firstNonEmpty(
            product["nutriscore_grade"] as? String,
            product["nutrition_grades"] as? String
        )?.lowercased()

        let novaGroup = intValue(product["nova_group"]) ?? intValue(product["nova_groups"])
        let additiveCount = intValue(product["additives_n"])

        let inputs = ProductScoreInputs(
            nutritionGrade: nutritionGrade,
            novaGroup: novaGroup,
            additiveCount: additiveCount
        )

        return inputs.hasSignals ? inputs : nil
    }

    private func intValue(_ value: Any?) -> Int? {
        switch value {
        case let intValue as Int:
            return intValue
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    func baseURL(for domain: ProductDomain) -> String {
        switch domain {
        case .food, .custom:
            return "https://world.openfoodfacts.org"
        case .beauty:
            return "https://world.openbeautyfacts.org"
        }
    }

    func ingredientsString(from value: Any?) -> String? {
        guard let list = value as? [[String: Any]] else { return nil }
        let parts = list.compactMap { firstNonEmpty($0["text"] as? String, $0["id"] as? String) }
        let joined = parts.joined(separator: ", ")
        return joined.isEmpty ? nil : joined
    }

    func firstNonEmpty(_ values: String?...) -> String? {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private enum LookupError: Error {
        case unavailable
    }
}

extension OpenFoodFactsService: ProductLookupServing {}
