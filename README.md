# Pg::Histogram
PostgreSQL histograms for ActiveRecord relations.

This plugin is inspired by [How to do histograms in PostgreSQL](https://blog.faraday.io/how-to-do-histograms-in-postgresql/) and [PostgreSQL, Aggregates and Histograms](https://tapoueh.org/blog/2014/02/postgresql-aggregates-and-histograms/).

## Usage

The following example is for a fictional [Ruby on Rails](https://rubyonrails.org/) for shopping.

### Prerequisites

Create the model for products:

```ruby
class Product < ApplicationRecord
  validates_numericality_of :price_usd, greater_than_or_equal_to: 0
end
```

Create the corresponding database migration:

```ruby
class CreateProducts < ActiveRecord::Migration[5.2]
  def change
    create_table :products do |t|
      t.price_usd, :float

      t.timestamps null: false
    end
  end
end
```

### Histogram with auto-sized bins

Create `Pg::Histogram` with 10 automatically-sized bins, calculated from the minimum and maximum prices, for the prices of all products:

```ruby
Pg::Histogram.for(Product.all, Product.arel_table[:price_usd], 10)
```

### Histogram with user-defined bins

Create a `Pg::Histogram` with 10 bins for the interval from $0 to $1000 for the prices of all products whose price is less than or equal to $1000:

```ruby
Pg::Histogram.for(Product.where(Product.arel_table[:price_usd].lteq(1000)), Product.arel_table[:price_usd], 10, min: 0, max: 1000)
```

## Installation
Add this line to your application's Gemfile:

```ruby
gem 'pg-histogram'
```

And then execute:
```bash
$ bundle
```

Or install it yourself as:
```bash
$ gem install pg-histogram
```

## Contributing
Contributions are accepted on [GitHub](https://github.com/) via the fork and pull request workflow. See [here](https://help.github.com/articles/using-pull-requests/) for more information.

## License
The gem is available as open source under the terms of [The 2-Clause BSD License](https://opensource.org/licenses/BSD-2-Clause).
